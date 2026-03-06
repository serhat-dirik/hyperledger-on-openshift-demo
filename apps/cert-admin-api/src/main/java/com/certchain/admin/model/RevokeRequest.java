package com.certchain.admin.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Request payload for revoking a certificate.
 */
@Schema(description = "Request payload for certificate revocation")
public record RevokeRequest(
    @Schema(description = "Reason for revoking the certificate", required = true, example = "Academic policy violation")
    String reason
) {}
