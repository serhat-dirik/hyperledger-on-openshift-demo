package com.certchain.verify.service;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import javax.imageio.ImageIO;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.nayuki.qrcodegen.QrCode;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Counter;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import com.certchain.verify.client.FabricGatewayClient;
import com.certchain.verify.model.VerificationResult;

import org.jboss.logging.Logger;

/**
 * Business logic for certificate verification.
 * Delegates blockchain interactions to FabricGatewayClient (read-only).
 */
@ApplicationScoped
public class VerificationService {

    private static final Logger LOG = Logger.getLogger(VerificationService.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Inject
    FabricGatewayClient fabricClient;

    @Inject
    MeterRegistry registry;

    private Counter verifiedCounter;
    private Counter notFoundCounter;

    @jakarta.annotation.PostConstruct
    void initCounters() {
        verifiedCounter = Counter.builder("certificate.verified")
                .description("Certificates verified")
                .register(registry);
        notFoundCounter = Counter.builder("certificate.not_found")
                .description("Certificate lookups not found")
                .register(registry);
    }

    /**
     * Verify a single certificate by ID.
     * Calls the VerifyCertificate chaincode function and maps the result
     * to a VerificationResult with status mapping:
     * ACTIVE -> VALID, REVOKED -> REVOKED, EXPIRED -> EXPIRED.
     *
     * @param certId the certificate ID to verify
     * @return the verification result
     * @throws CertificateNotFoundException if the certificate is not found
     * @throws VerificationException if a Fabric communication error occurs
     */
    public VerificationResult verify(String certId) {
        try {
            byte[] response = fabricClient.evaluateTransaction("VerifyCertificate", certId);
            JsonNode cert = MAPPER.readTree(response);

            String ledgerStatus = cert.path("status").asText("");
            String mappedStatus = mapStatus(ledgerStatus);
            String verifiedAt = Instant.now().toString();

            verifiedCounter.increment();

            // Public verification — omit private fields (grade, degree)
            return new VerificationResult(
                    cert.path("certID").asText(certId),
                    mappedStatus,
                    cert.path("studentName").asText(""),
                    cert.path("courseName").asText(""),
                    cert.path("orgName").asText(""),
                    cert.path("issueDate").asText(""),
                    cert.path("expiryDate").asText(""),
                    null,  // grade — private
                    null,  // degree — private
                    cert.path("revokeReason").asText(null),
                    verifiedAt
            );
        } catch (Exception e) {
            String message = e.getMessage() != null ? e.getMessage() : "";
            if (message.contains("not found") || message.contains("does not exist")) {
                LOG.debugf("Certificate not found: %s", certId);
                notFoundCounter.increment();
                throw new CertificateNotFoundException(certId);
            }
            LOG.errorf(e, "Failed to verify certificate: %s", certId);
            throw new VerificationException("Failed to verify certificate: " + certId, e);
        }
    }

    /**
     * Generate a QR code PNG image encoding the verification URL for a certificate.
     *
     * @param certId  the certificate ID
     * @param baseUrl the base URL of the student webapp
     * @return PNG image bytes
     */
    public byte[] generateQR(String certId, String baseUrl) {
        String url = baseUrl + "/result/" + certId;

        QrCode qr = QrCode.encodeText(url, QrCode.Ecc.MEDIUM);
        int scale = 8;
        int border = 4;
        int size = (qr.size + border * 2) * scale;

        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                int moduleX = x / scale - border;
                int moduleY = y / scale - border;
                boolean isBlack = moduleX >= 0 && moduleX < qr.size
                        && moduleY >= 0 && moduleY < qr.size
                        && qr.getModule(moduleX, moduleY);
                img.setRGB(x, y, isBlack ? 0x000000 : 0xFFFFFF);
            }
        }

        try {
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            ImageIO.write(img, "PNG", baos);
            return baos.toByteArray();
        } catch (IOException e) {
            LOG.errorf(e, "Failed to generate QR code for certificate: %s", certId);
            throw new VerificationException("Failed to generate QR code", e);
        }
    }

    /**
     * Get all certificates issued to a student, identified by student email or ID.
     * Calls the GetCertificatesByStudent chaincode function.
     *
     * @param studentIdentifier the student email or ID
     * @return list of verification results for the student
     * @throws VerificationException if a Fabric communication error occurs
     */
    public List<VerificationResult> getCertificatesByStudent(String studentIdentifier) {
        try {
            byte[] response = fabricClient.evaluateTransaction("GetCertificatesByStudent", studentIdentifier);
            JsonNode certs = MAPPER.readTree(response);
            String verifiedAt = Instant.now().toString();

            List<VerificationResult> results = new ArrayList<>();
            if (certs.isArray()) {
                for (JsonNode cert : certs) {
                    String ledgerStatus = cert.path("status").asText("");
                    // Transcript — include private fields (grade, degree)
                    results.add(new VerificationResult(
                            cert.path("certID").asText(""),
                            mapStatus(ledgerStatus),
                            cert.path("studentName").asText(""),
                            cert.path("courseName").asText(""),
                            cert.path("orgName").asText(""),
                            cert.path("issueDate").asText(""),
                            cert.path("expiryDate").asText(""),
                            cert.path("grade").asText(null),
                            cert.path("degree").asText(null),
                            cert.path("revokeReason").asText(null),
                            verifiedAt
                    ));
                }
            }
            return results;
        } catch (Exception e) {
            LOG.errorf(e, "Failed to get certificates for student: %s", studentIdentifier);
            throw new VerificationException("Failed to get certificates for student", e);
        }
    }

    /**
     * Verify multiple certificates in a batch.
     *
     * @param certIds the list of certificate IDs to verify
     * @return list of verification results (one per ID, including NOT_FOUND entries)
     */
    /**
     * Verify a certificate and include private fields (grade, degree).
     * Used by the authenticated transcript detail endpoint.
     */
    public VerificationResult verifyFull(String certId) {
        try {
            byte[] response = fabricClient.evaluateTransaction("VerifyCertificate", certId);
            JsonNode cert = MAPPER.readTree(response);

            String ledgerStatus = cert.path("status").asText("");
            String mappedStatus = mapStatus(ledgerStatus);
            String verifiedAt = Instant.now().toString();

            return new VerificationResult(
                    cert.path("certID").asText(certId),
                    mappedStatus,
                    cert.path("studentName").asText(""),
                    cert.path("courseName").asText(""),
                    cert.path("orgName").asText(""),
                    cert.path("issueDate").asText(""),
                    cert.path("expiryDate").asText(""),
                    cert.path("grade").asText(null),
                    cert.path("degree").asText(null),
                    cert.path("revokeReason").asText(null),
                    verifiedAt
            );
        } catch (Exception e) {
            String message = e.getMessage() != null ? e.getMessage() : "";
            if (message.contains("not found") || message.contains("does not exist")) {
                throw new CertificateNotFoundException(certId);
            }
            throw new VerificationException("Failed to verify certificate: " + certId, e);
        }
    }

    public List<VerificationResult> batchVerify(List<String> certIds) {
        List<VerificationResult> results = new ArrayList<>();
        for (String certId : certIds) {
            try {
                results.add(verify(certId));
            } catch (CertificateNotFoundException e) {
                results.add(new VerificationResult(
                        certId, "NOT_FOUND",
                        null, null, null, null, null, null, null, null,
                        Instant.now().toString()
                ));
            }
        }
        return results;
    }

    private String mapStatus(String ledgerStatus) {
        return switch (ledgerStatus) {
            case "ACTIVE" -> "VALID";
            case "REVOKED" -> "REVOKED";
            case "EXPIRED" -> "EXPIRED";
            default -> "UNKNOWN";
        };
    }

    /**
     * Thrown when a certificate is not found on the ledger.
     */
    public static class CertificateNotFoundException extends RuntimeException {
        private final String certId;

        public CertificateNotFoundException(String certId) {
            super("Certificate not found: " + certId);
            this.certId = certId;
        }

        public String getCertId() {
            return certId;
        }
    }

    /**
     * Thrown when a Fabric communication or processing error occurs.
     */
    public static class VerificationException extends RuntimeException {
        public VerificationException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
