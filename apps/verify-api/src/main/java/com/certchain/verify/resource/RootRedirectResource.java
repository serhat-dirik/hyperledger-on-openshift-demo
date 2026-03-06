package com.certchain.verify.resource;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

import java.net.URI;

/**
 * Redirects the API root to Swagger UI for interactive API exploration.
 */
@Path("/")
public class RootRedirectResource {

    @GET
    public Response redirectToSwagger() {
        return Response.temporaryRedirect(URI.create("/q/swagger-ui/")).build();
    }
}
