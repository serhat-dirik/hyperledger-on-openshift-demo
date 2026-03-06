package com.certchain.verify.resource;

import org.eclipse.microprofile.openapi.annotations.OpenAPIDefinition;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.info.Info;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;

@OpenAPIDefinition(
    info = @Info(
        title = "CertChain Verification API",
        version = "1.0.0",
        description = "Public certificate verification and authenticated student transcript API."
    )
)
@SecurityScheme(
    securitySchemeName = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT",
    description = "Obtain a token from the central Keycloak (POST /realms/certchain/protocol/openid-connect/token). Required only for /api/v1/transcript endpoints."
)
public class OpenAPIConfig {
}
