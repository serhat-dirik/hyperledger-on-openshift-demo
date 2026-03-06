package com.certchain.admin.resource;

import com.certchain.admin.model.DashboardStats;
import com.certchain.admin.service.CertificateService;

import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import org.eclipse.microprofile.jwt.JsonWebToken;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;
import org.jboss.logging.Logger;

/**
 * REST resource for the admin dashboard.
 * Returns aggregated certificate statistics scoped to the caller's organization.
 */
@Path("/api/v1/dashboard")
@Produces(MediaType.APPLICATION_JSON)
@RolesAllowed("org-admin")
@Tag(name = "Dashboard", description = "Aggregated certificate statistics for the organization dashboard")
public class DashboardResource {

    private static final Logger LOG = Logger.getLogger(DashboardResource.class);

    @Inject
    CertificateService certificateService;

    @Inject
    JsonWebToken jwt;

    @GET
    @Path("/stats")
    @Operation(summary = "Get dashboard statistics", description = "Returns certificate counts (total, active, revoked, expired) for the caller's organization.")
    @APIResponse(responseCode = "200", description = "Dashboard statistics")
    public Response getStats() {
        String orgId = getOrgId();

        try {
            DashboardStats stats = certificateService.getStats(orgId);
            return Response.ok(stats).build();
        } catch (Exception e) {
            LOG.errorf(e, "Failed to get dashboard stats for org: %s", orgId);
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity("{\"error\":\"Failed to retrieve dashboard statistics\"}")
                    .build();
        }
    }

    private String getOrgId() {
        Object orgId = jwt.getClaim("org_id");
        if (orgId == null) {
            throw new WebApplicationException("Missing org_id claim in token", Response.Status.FORBIDDEN);
        }
        return orgId.toString();
    }
}
