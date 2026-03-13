package com.certchain.verify.resource;

import java.util.List;
import java.util.Map;

import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import io.quarkus.security.identity.SecurityIdentity;

import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

import com.certchain.verify.model.VerificationResult;
import com.certchain.verify.service.VerificationService;
import com.certchain.verify.service.VerificationService.CertificateNotFoundException;
import com.certchain.verify.service.VerificationService.VerificationException;

/**
 * Authenticated REST resource for student transcript access.
 * Requires a valid JWT from the central Keycloak.
 * Students log in via identity brokering (org KC → central KC).
 */
@Path("/api/v1/transcript")
@Produces(MediaType.APPLICATION_JSON)
@Tag(name = "Transcript", description = "Authenticated student transcript access (requires central KC token via identity brokering)")
@SecurityRequirement(name = "bearerAuth")
public class TranscriptResource {

    @Inject
    VerificationService verificationService;

    @Inject
    SecurityIdentity identity;

    /**
     * Get all certificates for the authenticated student.
     * Uses the student's email from the JWT to query the ledger.
     */
    @GET
    @Operation(summary = "Get student transcript", description = "Returns all certificates for the authenticated student, identified by email from the JWT token.")
    @APIResponse(responseCode = "200", description = "Array of certificates for the student")
    @APIResponse(responseCode = "400", description = "Student identity not found in token")
    public Response getTranscript() {
        String studentEmail = identity.getPrincipal().getName();
        if (studentEmail == null || studentEmail.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", "Student identity not found in token"))
                    .build();
        }

        try {
            List<VerificationResult> certs = verificationService.getCertificatesByStudent(studentEmail);
            return Response.ok(certs).build();
        } catch (VerificationException e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(Map.of("error", "Failed to retrieve transcript"))
                    .build();
        }
    }

    /**
     * Get detailed information for a specific certificate.
     * Only accessible to authenticated students.
     */
    @GET
    @Path("/{certId}")
    @Operation(summary = "Get certificate detail", description = "Returns detailed information for a specific certificate. Requires student authentication.")
    @APIResponse(responseCode = "200", description = "Certificate details")
    @APIResponse(responseCode = "404", description = "Certificate not found")
    public Response getCertificateDetail(@Parameter(description = "Certificate ID", required = true) @PathParam("certId") String certId) {
        try {
            String studentEmail = identity.getPrincipal().getName();
            VerificationResult result = verificationService.verifyForStudent(certId, studentEmail);
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
}
