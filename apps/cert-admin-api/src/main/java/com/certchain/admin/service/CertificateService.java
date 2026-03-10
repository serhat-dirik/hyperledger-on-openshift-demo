package com.certchain.admin.service;

import java.util.ArrayList;
import java.util.List;

import com.certchain.admin.client.FabricGatewayClient;
import com.certchain.admin.model.CertificateDTO;
import com.certchain.admin.model.DashboardStats;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Counter;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import org.jboss.logging.Logger;

/**
 * Business logic for certificate operations.
 * Delegates blockchain interactions to FabricGatewayClient.
 */
@ApplicationScoped
public class CertificateService {

    private static final Logger LOG = Logger.getLogger(CertificateService.class);

    @Inject
    FabricGatewayClient fabricClient;

    @Inject
    MeterRegistry registry;

    private Counter issuedCounter;
    private Counter revokedCounter;

    @jakarta.annotation.PostConstruct
    void initCounters() {
        issuedCounter = Counter.builder("certificate.issued")
                .description("Certificates issued")
                .register(registry);
        revokedCounter = Counter.builder("certificate.revoked")
                .description("Certificates revoked")
                .register(registry);
    }

    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Issue a new certificate on the blockchain ledger.
     */
    public CertificateDTO issue(CertificateDTO dto) throws Exception {
        LOG.infof("Issuing certificate: certID=%s, orgID=%s, studentID=%s",
                dto.certID(), dto.orgID(), dto.studentID());

        fabricClient.submitTransaction("IssueCertificate",
                dto.certID(),
                dto.studentID(),
                dto.studentName(),
                dto.courseID(),
                dto.courseName(),
                dto.orgID(),
                dto.orgName(),
                dto.issueDate(),
                dto.expiryDate(),
                dto.grade() != null ? dto.grade() : "",
                dto.degree() != null ? dto.degree() : "",
                "");

        issuedCounter.increment();

        // Read back the issued certificate from the ledger to return full data
        return get(dto.certID());
    }

    /**
     * Retrieve a single certificate by its ID.
     */
    public CertificateDTO get(String certId) throws Exception {
        LOG.debugf("Getting certificate: certID=%s", certId);

        byte[] result = fabricClient.evaluateTransaction("GetCertificate", certId);
        if (result == null || result.length == 0) {
            return null;
        }
        return objectMapper.readValue(result, CertificateDTO.class);
    }

    /**
     * List all certificates for a given organization.
     */
    public List<CertificateDTO> listByOrg(String orgId) throws Exception {
        LOG.debugf("Listing certificates for org: %s", orgId);

        byte[] result = fabricClient.evaluateTransaction("GetCertificatesByOrg", orgId);
        if (result == null || result.length == 0) {
            return new ArrayList<>();
        }

        String json = new String(result);
        // The chaincode returns a Go slice which may be null (marshaled as "null")
        if ("null".equals(json) || json.isBlank()) {
            return new ArrayList<>();
        }

        return objectMapper.readValue(result, new TypeReference<List<CertificateDTO>>() {});
    }

    /**
     * Revoke a certificate with a reason.
     */
    public void revoke(String certId, String reason) throws Exception {
        LOG.infof("Revoking certificate: certID=%s, reason=%s", certId, reason);

        fabricClient.submitTransaction("RevokeCertificate", certId, reason);

        revokedCounter.increment();
    }

    /**
     * Compute dashboard statistics for an organization by counting
     * certificates in each status (ACTIVE, REVOKED, EXPIRED).
     */
    public DashboardStats getStats(String orgId) throws Exception {
        LOG.debugf("Getting dashboard stats for org: %s", orgId);

        List<CertificateDTO> certs = listByOrg(orgId);

        int total = certs.size();
        int active = 0;
        int revoked = 0;
        int expired = 0;

        for (CertificateDTO cert : certs) {
            if (cert.status() == null) {
                continue;
            }
            switch (cert.status()) {
                case "ACTIVE" -> active++;
                case "REVOKED" -> revoked++;
                case "EXPIRED" -> expired++;
                default -> LOG.warnf("Unknown certificate status: %s for certID=%s", cert.status(), cert.certID());
            }
        }

        return new DashboardStats(total, active, revoked, expired);
    }
}
