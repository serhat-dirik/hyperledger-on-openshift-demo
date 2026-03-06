package com.certchain.verify.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Schema(description = "Certificate verification result from the Hyperledger Fabric ledger")
public record VerificationResult(
    @Schema(description = "Certificate identifier", example = "TP-2026-001")
    String certID,
    @Schema(description = "Verification status", example = "VALID", enumeration = {"VALID", "REVOKED", "EXPIRED", "NOT_FOUND"})
    String status,
    @Schema(description = "Student full name", example = "Jane Doe")
    String studentName,
    @Schema(description = "Course display name", example = "Full-Stack Web Dev")
    String courseName,
    @Schema(description = "Issuing organization name", example = "TechPulse Academy")
    String orgName,
    @Schema(description = "Certificate issue date (ISO 8601)", example = "2026-03-06")
    String issueDate,
    @Schema(description = "Certificate expiry date (ISO 8601)", example = "2028-12-31")
    String expiryDate,
    @Schema(description = "Reason for revocation, if applicable")
    String revokeReason,
    @Schema(description = "Timestamp of this verification query (ISO 8601)")
    String verifiedAt
) {}
