package com.certchain.admin.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Request payload for issuing a new certificate.
 * orgID and orgName are derived from the authenticated user's JWT claims.
 */
@Schema(description = "Request payload for issuing a new certificate")
public record IssueCertificateRequest(
    @Schema(description = "Unique certificate identifier", required = true, example = "TP-2026-001")
    String certID,
    @Schema(description = "Student identifier", required = true, example = "student01")
    String studentID,
    @Schema(description = "Student full name", example = "Jane Doe")
    String studentName,
    @Schema(description = "Course identifier", required = true, example = "FSWD-101")
    String courseID,
    @Schema(description = "Course display name", example = "Full-Stack Web Dev")
    String courseName,
    @Schema(description = "Issue date (ISO 8601)", example = "2026-03-06")
    String issueDate,
    @Schema(description = "Expiry date (ISO 8601)", example = "2028-12-31")
    String expiryDate,
    @Schema(description = "Optional metadata (JSON string)")
    String metadata
) {}
