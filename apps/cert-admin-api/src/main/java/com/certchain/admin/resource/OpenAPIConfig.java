package com.certchain.admin.resource;

import org.eclipse.microprofile.openapi.annotations.OpenAPIDefinition;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.info.Info;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;

@OpenAPIDefinition(
    info = @Info(
        title = "CertChain Admin API",
        version = "1.0.0",
        description = "REST API for training institute administrators to issue and manage blockchain-anchored certificates."
    ),
    security = @SecurityRequirement(name = "bearerAuth")
)
@SecurityScheme(
    securitySchemeName = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT",
    description = "Obtain a token from the per-org Keycloak (e.g. POST /realms/techpulse/protocol/openid-connect/token with client_id=course-manager-ui, grant_type=password)"
)
public class OpenAPIConfig {
}
