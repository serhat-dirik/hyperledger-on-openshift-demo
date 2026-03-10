package com.certchain.admin.resource;

import com.certchain.admin.client.FabricGatewayClient;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.quarkus.test.security.oidc.Claim;
import io.quarkus.test.security.oidc.OidcSecurity;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

@QuarkusTest
class DashboardResourceTest {

    @InjectMock
    FabricGatewayClient fabricClient;

    /**
     * Returns a JSON array of certificates with mixed statuses for stats computation.
     * 3 ACTIVE, 1 REVOKED, 1 EXPIRED = 5 total
     */
    private static String certListWithMixedStatuses() {
        return """
                [
                  {
                    "certID": "TP-2026-001", "studentID": "s01", "studentName": "Alice",
                    "courseID": "FSWD-101", "courseName": "Full-Stack Web Dev",
                    "orgID": "techpulse", "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15", "expiryDate": "2028-12-31",
                    "status": "ACTIVE", "revokeReason": null, "metadata": "",
                    "txID": "tx-001", "timestamp": "2026-01-15T10:00:00Z"
                  },
                  {
                    "certID": "TP-2026-002", "studentID": "s02", "studentName": "Bob",
                    "courseID": "CNM-201", "courseName": "Cloud-Native Microservices",
                    "orgID": "techpulse", "orgName": "TechPulse Academy",
                    "issueDate": "2026-02-10", "expiryDate": "2028-12-31",
                    "status": "ACTIVE", "revokeReason": null, "metadata": "",
                    "txID": "tx-002", "timestamp": "2026-02-10T11:00:00Z"
                  },
                  {
                    "certID": "TP-2026-003", "studentID": "s03", "studentName": "Carol",
                    "courseID": "DSO-301", "courseName": "DevSecOps Fundamentals",
                    "orgID": "techpulse", "orgName": "TechPulse Academy",
                    "issueDate": "2026-02-20", "expiryDate": "2028-12-31",
                    "status": "ACTIVE", "revokeReason": null, "metadata": "",
                    "txID": "tx-003", "timestamp": "2026-02-20T09:30:00Z"
                  },
                  {
                    "certID": "TP-2025-010", "studentID": "s04", "studentName": "Dave",
                    "courseID": "FSWD-101", "courseName": "Full-Stack Web Dev",
                    "orgID": "techpulse", "orgName": "TechPulse Academy",
                    "issueDate": "2025-01-10", "expiryDate": "2025-12-31",
                    "status": "REVOKED", "revokeReason": "Academic misconduct", "metadata": "",
                    "txID": "tx-010", "timestamp": "2025-01-10T08:00:00Z"
                  },
                  {
                    "certID": "TP-2024-005", "studentID": "s05", "studentName": "Eve",
                    "courseID": "CNM-201", "courseName": "Cloud-Native Microservices",
                    "orgID": "techpulse", "orgName": "TechPulse Academy",
                    "issueDate": "2024-03-15", "expiryDate": "2025-03-15",
                    "status": "EXPIRED", "revokeReason": null, "metadata": "",
                    "txID": "tx-005", "timestamp": "2024-03-15T14:00:00Z"
                  }
                ]
                """;
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetDashboardStats() throws Exception {
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenReturn(certListWithMixedStatuses().getBytes());

        given()
                .when()
                .get("/api/v1/dashboard/stats")
                .then()
                .statusCode(200)
                .body("totalCerts", equalTo(5))
                .body("activeCerts", equalTo(3))
                .body("revokedCerts", equalTo(1))
                .body("expiredCerts", equalTo(1));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetDashboardStatsEmpty() throws Exception {
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenReturn(new byte[0]);

        given()
                .when()
                .get("/api/v1/dashboard/stats")
                .then()
                .statusCode(200)
                .body("totalCerts", equalTo(0))
                .body("activeCerts", equalTo(0))
                .body("revokedCerts", equalTo(0))
                .body("expiredCerts", equalTo(0));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetDashboardStatsFabricError() throws Exception {
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenThrow(new RuntimeException("Fabric peer unavailable"));

        given()
                .when()
                .get("/api/v1/dashboard/stats")
                .then()
                .statusCode(500)
                .body("error", containsString("Failed to retrieve dashboard statistics"));
    }

    @Test
    void testGetDashboardStatsUnauthorized() {
        given()
                .when()
                .get("/api/v1/dashboard/stats")
                .then()
                .statusCode(401);
    }
}
