package com.certchain.admin.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Aggregated certificate statistics for the admin dashboard.
 */
@Schema(description = "Aggregated certificate statistics for the organization dashboard")
public record DashboardStats(
    @Schema(description = "Total number of certificates", example = "42")
    int totalCerts,
    @Schema(description = "Number of active (valid) certificates", example = "35")
    int activeCerts,
    @Schema(description = "Number of revoked certificates", example = "5")
    int revokedCerts,
    @Schema(description = "Number of expired certificates", example = "2")
    int expiredCerts
) {}
