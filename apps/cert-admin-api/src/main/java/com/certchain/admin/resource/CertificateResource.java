package com.certchain.admin.resource;

import java.util.List;

import com.certchain.admin.model.CertificateDTO;
import com.certchain.admin.model.IssueCertificateRequest;
import com.certchain.admin.model.RevokeRequest;
import com.certchain.admin.model.UpdateCertificateRequest;
import com.certchain.admin.service.CertificateService;

import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import org.eclipse.microprofile.jwt.JsonWebToken;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;
import org.jboss.logging.Logger;

/**
 * REST resource for certificate management.
 * All endpoints require the org-admin role via Keycloak OIDC.
 * The org_id claim from the JWT token scopes operations to the caller's organization.
 */
@Path("/api/v1/certificates")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@RolesAllowed("org-admin")
@Tag(name = "Certificates", description = "Issue, list, retrieve, and revoke blockchain-anchored certificates")
public class CertificateResource {

    private static final Logger LOG = Logger.getLogger(CertificateResource.class);

    @Inject
    CertificateService certificateService;

    @Inject
    JsonWebToken jwt;

    @POST
    @Operation(summary = "Issue a new certificate", description = "Creates a new certificate on the Hyperledger Fabric ledger. The issuing organization is derived from the JWT token.")
    @APIResponse(responseCode = "201", description = "Certificate issued successfully")
    @APIResponse(responseCode = "400", description = "Missing required fields")
    @APIResponse(responseCode = "409", description = "Certificate ID already exists")
    public Response issueCertificate(IssueCertificateRequest request) {
        String orgId = getOrgId();
        String orgName = getOrgName();

        if (request == null || request.certID() == null || request.certID().isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("certID is required"))
                    .build();
        }
        if (request.studentID() == null || request.studentID().isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("studentID is required"))
                    .build();
        }
        if (!request.studentID().matches("^[A-Za-z0-9][A-Za-z0-9._@-]{1,63}$")) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("studentID must be 2-64 alphanumeric characters (hyphens, dots, underscores, @ allowed)"))
                    .build();
        }
        if (request.studentName() == null || request.studentName().isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("studentName is required"))
                    .build();
        }
        String trimmedName = request.studentName().trim();
        if (trimmedName.length() < 3 || !trimmedName.contains(" ")) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("studentName must be a full name (first and last name, minimum 3 characters)"))
                    .build();
        }
        if (request.courseID() == null || request.courseID().isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("courseID is required"))
                    .build();
        }

        // Build a full DTO with org info from the authenticated token
        CertificateDTO dto = new CertificateDTO(
                request.certID(),
                request.studentID(),
                request.studentName(),
                request.courseID(),
                request.courseName(),
                orgId,
                orgName,
                request.issueDate(),
                request.expiryDate(),
                request.grade(),
                request.degree(),
                null,  // status — set by chaincode
                null,  // revokeReason
                request.metadata() != null ? request.metadata() : "",  // metadata
                null,  // txID — set by chaincode
                null   // timestamp — set by chaincode
        );

        try {
            CertificateDTO issued = certificateService.issue(dto);
            return Response.status(Response.Status.CREATED).entity(issued).build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to issue certificate: %s", request.certID());
            if (e.getMessage() != null && e.getMessage().contains("already exists")) {
                return Response.status(Response.Status.CONFLICT)
                        .entity(errorJson("Certificate " + request.certID() + " already exists"))
                        .build();
            }
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(errorJson("Failed to issue certificate: " + e.getMessage()))
                    .build();
        }
    }

    @GET
    @Operation(summary = "List certificates", description = "Returns a paginated list of certificates for the caller's organization.")
    @APIResponse(responseCode = "200", description = "List of certificates with X-Total-Count header")
    public Response listCertificates(
            @Parameter(description = "Page number (0-based)") @QueryParam("page") @DefaultValue("0") int page,
            @Parameter(description = "Page size") @QueryParam("size") @DefaultValue("20") int size) {
        String orgId = getOrgId();

        try {
            List<CertificateDTO> allCerts = certificateService.listByOrg(orgId);

            // Simple pagination over the full list
            int fromIndex = Math.min(page * size, allCerts.size());
            int toIndex = Math.min(fromIndex + size, allCerts.size());
            List<CertificateDTO> pagedCerts = allCerts.subList(fromIndex, toIndex);

            return Response.ok(pagedCerts)
                    .header("X-Total-Count", allCerts.size())
                    .build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to list certificates for org: %s", orgId);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(errorJson("Failed to list certificates: " + e.getMessage()))
                    .build();
        }
    }

    @GET
    @Path("/{certId}")
    @Operation(summary = "Get a certificate", description = "Retrieves a single certificate by ID. Must belong to the caller's organization.")
    @APIResponse(responseCode = "200", description = "Certificate details")
    @APIResponse(responseCode = "404", description = "Certificate not found")
    @APIResponse(responseCode = "403", description = "Certificate belongs to a different organization")
    public Response getCertificate(@Parameter(description = "Certificate ID", required = true) @PathParam("certId") String certId) {
        String orgId = getOrgId();

        try {
            CertificateDTO cert = certificateService.get(certId);
            if (cert == null) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }

            // Verify the certificate belongs to the caller's organization
            if (!orgId.equals(cert.orgID())) {
                return Response.status(Response.Status.FORBIDDEN)
                        .entity(errorJson("Certificate does not belong to your organization"))
                        .build();
            }

            return Response.ok(cert).build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to get certificate: %s", certId);
            if (e.getMessage() != null && e.getMessage().contains("not found")) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(errorJson("Failed to get certificate: " + e.getMessage()))
                    .build();
        }
    }

    @PUT
    @Path("/{certId}")
    @Operation(summary = "Update a certificate", description = "Updates mutable fields (grade, degree) on an existing certificate.")
    @APIResponse(responseCode = "200", description = "Certificate updated, updated record returned")
    @APIResponse(responseCode = "404", description = "Certificate not found")
    @APIResponse(responseCode = "403", description = "Certificate belongs to a different organization")
    public Response updateCertificate(@Parameter(description = "Certificate ID", required = true) @PathParam("certId") String certId, UpdateCertificateRequest request) {
        String orgId = getOrgId();

        try {
            CertificateDTO cert = certificateService.get(certId);
            if (cert == null) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }
            if (!orgId.equals(cert.orgID())) {
                return Response.status(Response.Status.FORBIDDEN)
                        .entity(errorJson("Certificate does not belong to your organization"))
                        .build();
            }

            CertificateDTO updated = certificateService.update(certId,
                    request != null ? request.grade() : null,
                    request != null ? request.degree() : null);
            return Response.ok(updated).build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to update certificate: %s", certId);
            if (e.getMessage() != null && e.getMessage().contains("not found")) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(errorJson("Failed to update certificate: " + e.getMessage()))
                    .build();
        }
    }

    @PUT
    @Path("/{certId}/revoke")
    @Operation(summary = "Revoke a certificate", description = "Permanently revokes a certificate on the blockchain. This action is irreversible.")
    @APIResponse(responseCode = "200", description = "Certificate revoked, updated record returned")
    @APIResponse(responseCode = "400", description = "Missing revocation reason")
    @APIResponse(responseCode = "404", description = "Certificate not found")
    @APIResponse(responseCode = "409", description = "Certificate is already revoked")
    public Response revokeCertificate(@Parameter(description = "Certificate ID", required = true) @PathParam("certId") String certId, RevokeRequest request) {
        String orgId = getOrgId();

        if (request == null || request.reason() == null || request.reason().isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(errorJson("Revocation reason is required"))
                    .build();
        }

        try {
            // Verify the certificate belongs to the caller's org before revoking
            CertificateDTO cert = certificateService.get(certId);
            if (cert == null) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }
            if (!orgId.equals(cert.orgID())) {
                return Response.status(Response.Status.FORBIDDEN)
                        .entity(errorJson("Certificate does not belong to your organization"))
                        .build();
            }

            certificateService.revoke(certId, request.reason());

            // Return the updated certificate
            CertificateDTO revoked = certificateService.get(certId);
            return Response.ok(revoked).build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to revoke certificate: %s", certId);
            if (e.getMessage() != null && e.getMessage().contains("already revoked")) {
                return Response.status(Response.Status.CONFLICT)
                        .entity(errorJson("Certificate " + certId + " is already revoked"))
                        .build();
            }
            if (e.getMessage() != null && e.getMessage().contains("not found")) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(errorJson("Certificate not found: " + certId))
                        .build();
            }
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(errorJson("Failed to revoke certificate: " + e.getMessage()))
                    .build();
        }
    }

    /**
     * Extract org_id from the JWT token claims.
     */
    private String getOrgId() {
        Object orgId = jwt.getClaim("org_id");
        if (orgId == null) {
            throw new WebApplicationException("Missing org_id claim in token", Response.Status.FORBIDDEN);
        }
        return orgId.toString();
    }

    /**
     * Extract org_name from the JWT token claims, with fallback to org_id.
     */
    private String getOrgName() {
        Object orgName = jwt.getClaim("org_name");
        if (orgName != null) {
            return orgName.toString();
        }
        // Fallback: derive a display name from the org_id
        String orgId = getOrgId();
        return switch (orgId) {
            case "techpulse" -> "TechPulse Academy";
            case "dataforge" -> "DataForge Institute";
            case "neuralpath" -> "NeuralPath Labs";
            default -> orgId;
        };
    }

    private static String errorJson(String message) {
        return "{\"error\":\"" + message.replace("\"", "\\\"") + "\"}";
    }
}
