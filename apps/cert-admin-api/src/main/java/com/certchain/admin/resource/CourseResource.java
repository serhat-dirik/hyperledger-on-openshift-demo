package com.certchain.admin.resource;

import java.util.Collections;
import java.util.List;
import java.util.Map;

import com.certchain.admin.model.CourseDTO;

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
 * REST resource for retrieving available courses per organization.
 * Course catalogs are hardcoded per the three demo training institutes.
 */
@Path("/api/v1/courses")
@Produces(MediaType.APPLICATION_JSON)
@RolesAllowed("org-admin")
@Tag(name = "Courses", description = "Retrieve available course catalog for the authenticated organization")
public class CourseResource {

    private static final Logger LOG = Logger.getLogger(CourseResource.class);

    /**
     * Hardcoded course catalogs for the three fictional training institutes.
     */
    private static final Map<String, List<CourseDTO>> COURSE_CATALOG = Map.of(
            "techpulse", List.of(
                    new CourseDTO("FSWD-101", "Full-Stack Web Dev"),
                    new CourseDTO("CNM-201", "Cloud-Native Microservices"),
                    new CourseDTO("DSO-301", "DevSecOps Fundamentals")
            ),
            "dataforge", List.of(
                    new CourseDTO("PGA-101", "PostgreSQL Administration"),
                    new CourseDTO("DPE-201", "Data Pipeline Engineering"),
                    new CourseDTO("GDB-301", "Graph Databases Masterclass")
            ),
            "neuralpath", List.of(
                    new CourseDTO("AML-101", "Applied Machine Learning"),
                    new CourseDTO("LFT-201", "LLM Fine-Tuning Workshop"),
                    new CourseDTO("CVP-301", "Computer Vision Practicum")
            )
    );

    @Inject
    JsonWebToken jwt;

    @GET
    @Operation(summary = "List available courses", description = "Returns the course catalog for the caller's organization (TechPulse, DataForge, or NeuralPath).")
    @APIResponse(responseCode = "200", description = "Array of available courses")
    public Response listCourses() {
        String orgId = getOrgId();

        List<CourseDTO> courses = COURSE_CATALOG.getOrDefault(orgId, Collections.emptyList());

        if (courses.isEmpty()) {
            LOG.warnf("No course catalog found for org: %s", orgId);
        }

        return Response.ok(courses).build();
    }

    private String getOrgId() {
        Object orgId = jwt.getClaim("org_id");
        if (orgId == null) {
            throw new WebApplicationException("Missing org_id claim in token", Response.Status.FORBIDDEN);
        }
        return orgId.toString();
    }
}
