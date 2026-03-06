package com.certchain.verify.resource;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

import com.certchain.verify.model.VerificationResult;
import com.certchain.verify.service.VerificationService;
import com.certchain.verify.service.VerificationService.CertificateNotFoundException;
import com.certchain.verify.service.VerificationService.VerificationException;

/**
 * Public REST resource for certificate verification.
 * No authentication required for single verify.
 */
@Path("/api/v1/verify")
@Produces(MediaType.APPLICATION_JSON)
@Tag(name = "Verification", description = "Public certificate verification endpoints (no authentication required)")
public class VerifyResource {

    @Inject
    VerificationService verificationService;

    @ConfigProperty(name = "certchain.verify.base-url")
    String baseUrl;

    /**
     * Verify a single certificate by ID.
     *
     * @param certId the certificate ID
     * @return 200 with VerificationResult, or 404 if not found
     */
    @GET
    @Path("/{certId}")
    @Operation(summary = "Verify a certificate", description = "Queries the Hyperledger Fabric ledger for certificate status. Returns VALID, REVOKED, EXPIRED, or NOT_FOUND.")
    @APIResponse(responseCode = "200", description = "Verification result")
    @APIResponse(responseCode = "404", description = "Certificate not found on the ledger")
    public Response verifyCertificate(@Parameter(description = "Certificate ID to verify", required = true, example = "TP-2026-001") @PathParam("certId") String certId) {
        try {
            VerificationResult result = verificationService.verify(certId);
            return Response.ok(result).build();
        } catch (CertificateNotFoundException e) {
            return Response.status(Response.Status.NOT_FOUND)
                    .entity(Map.of("certID", certId, "status", "NOT_FOUND"))
                    .build();
        } catch (VerificationException e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(Map.of("error", "Verification service unavailable"))
                    .build();
        }
    }

    /**
     * Generate a QR code PNG image for a certificate verification URL.
     *
     * @param certId the certificate ID
     * @return 200 with PNG image bytes
     */
    @GET
    @Path("/{certId}/qr")
    @Produces("image/png")
    @Operation(summary = "Generate verification QR code", description = "Returns a PNG image containing a QR code that links to the CertChain Portal verification page for this certificate.")
    @APIResponse(responseCode = "200", description = "QR code PNG image")
    public Response getQRCode(@Parameter(description = "Certificate ID", required = true) @PathParam("certId") String certId) {
        try {
            byte[] qrImage = verificationService.generateQR(certId, baseUrl);
            return Response.ok(qrImage).type("image/png").build();
        } catch (VerificationException e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .type(MediaType.APPLICATION_JSON)
                    .entity(Map.of("error", "Failed to generate QR code"))
                    .build();
        }
    }

    /**
     * Verify multiple certificates in a batch.
     *
     * @param commaSeparatedIds comma-separated list of certificate IDs
     * @return 200 with array of VerificationResult
     */
    @GET
    @Path("/batch")
    @Operation(summary = "Batch verify certificates", description = "Verifies multiple certificates in a single request. Pass comma-separated IDs.")
    @APIResponse(responseCode = "200", description = "Array of verification results")
    @APIResponse(responseCode = "400", description = "Missing or empty ids parameter")
    public Response batchVerify(@Parameter(description = "Comma-separated certificate IDs", required = true, example = "TP-2026-001,TP-2026-002") @QueryParam("ids") String commaSeparatedIds) {
        if (commaSeparatedIds == null || commaSeparatedIds.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", "Query parameter 'ids' is required"))
                    .build();
        }

        List<String> certIds = Arrays.stream(commaSeparatedIds.split(","))
                .map(String::trim)
                .filter(id -> !id.isEmpty())
                .toList();

        if (certIds.isEmpty()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", "No valid certificate IDs provided"))
                    .build();
        }

        try {
            List<VerificationResult> results = verificationService.batchVerify(certIds);
            return Response.ok(results).build();
        } catch (VerificationException e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(Map.of("error", "Verification service unavailable"))
                    .build();
        }
    }
}
