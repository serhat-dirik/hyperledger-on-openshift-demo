package com.certchain.admin.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Schema(description = "Request payload for updating certificate fields")
public record UpdateCertificateRequest(
    @Schema(description = "Grade or score achieved", example = "A")
    String grade,
    @Schema(description = "Degree or credential type", example = "Professional Certificate")
    String degree
) {}
