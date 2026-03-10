package com.certchain.admin.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Schema(description = "Certificate record anchored on the Hyperledger Fabric ledger")
@JsonIgnoreProperties(ignoreUnknown = true)
public record CertificateDTO(
    @Schema(description = "Unique certificate identifier", example = "TP-2026-001")
    String certID,
    @Schema(description = "Student identifier", example = "student01")
    String studentID,
    @Schema(description = "Student full name", example = "Jane Doe")
    String studentName,
    @Schema(description = "Course identifier", example = "FSWD-101")
    String courseID,
    @Schema(description = "Course display name", example = "Full-Stack Web Dev")
    String courseName,
    @Schema(description = "Issuing organization ID", example = "techpulse")
    String orgID,
    @Schema(description = "Issuing organization name", example = "TechPulse Academy")
    String orgName,
    @Schema(description = "Certificate issue date (ISO 8601)", example = "2026-03-06")
    String issueDate,
    @Schema(description = "Certificate expiry date (ISO 8601)", example = "2028-12-31")
    String expiryDate,
    @Schema(description = "Grade or score achieved", example = "A")
    String grade,
    @Schema(description = "Degree or credential type", example = "Professional Certificate")
    String degree,
    @Schema(description = "Certificate status", example = "ACTIVE", enumeration = {"ACTIVE", "REVOKED", "EXPIRED"})
    String status,
    @Schema(description = "Reason for revocation, if applicable")
    String revokeReason,
    @Schema(description = "Optional metadata (JSON string)")
    String metadata,
    @Schema(description = "Fabric transaction ID")
    String txID,
    @Schema(description = "Ledger timestamp")
    String timestamp
) {}
