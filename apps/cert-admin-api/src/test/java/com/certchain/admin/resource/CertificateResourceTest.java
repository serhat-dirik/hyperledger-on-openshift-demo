package com.certchain.admin.resource;

import com.certchain.admin.client.FabricGatewayClient;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit5.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.quarkus.test.security.oidc.Claim;
import io.quarkus.test.security.oidc.OidcSecurity;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

@QuarkusTest
class CertificateResourceTest {

    @InjectMock
    FabricGatewayClient fabricClient;

    // -- JSON helpers --

    private static String sampleCertJson(String certID, String status) {
        return """
                {
                  "certID": "%s",
                  "studentID": "student01",
                  "studentName": "Jane Doe",
                  "courseID": "FSWD-101",
                  "courseName": "Full-Stack Web Dev",
                  "orgID": "techpulse",
                  "orgName": "TechPulse Academy",
                  "issueDate": "2026-03-06",
                  "expiryDate": "2028-12-31",
                  "status": "%s",
                  "revokeReason": null,
                  "metadata": "",
                  "txID": "tx-abc-123",
                  "timestamp": "2026-03-06T10:00:00Z"
                }
                """.formatted(certID, status);
    }

    private static String sampleCertListJson() {
        return """
                [
                  {
                    "certID": "TP-2026-001",
                    "studentID": "student01",
                    "studentName": "Jane Doe",
                    "courseID": "FSWD-101",
                    "courseName": "Full-Stack Web Dev",
                    "orgID": "techpulse",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-03-06",
                    "expiryDate": "2028-12-31",
                    "status": "ACTIVE",
                    "revokeReason": null,
                    "metadata": "",
                    "txID": "tx-abc-001",
                    "timestamp": "2026-03-06T10:00:00Z"
                  },
                  {
                    "certID": "TP-2026-002",
                    "studentID": "student02",
                    "studentName": "John Smith",
                    "courseID": "CNM-201",
                    "courseName": "Cloud-Native Microservices",
                    "orgID": "techpulse",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-03-07",
                    "expiryDate": "2028-12-31",
                    "status": "ACTIVE",
                    "revokeReason": null,
                    "metadata": "",
                    "txID": "tx-abc-002",
                    "timestamp": "2026-03-07T11:00:00Z"
                  }
                ]
                """;
    }

    // -- Issue certificate --

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse"),
            @Claim(key = "org_name", value = "TechPulse Academy")
    })
    void testIssueCertificate() throws Exception {
        // After submitTransaction, the service calls evaluateTransaction("GetCertificate", certID)
        String certJson = sampleCertJson("TP-2026-001", "ACTIVE");
        Mockito.when(fabricClient.submitTransaction(Mockito.eq("IssueCertificate"), Mockito.any(String[].class)))
                .thenReturn(new byte[0]);
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(certJson.getBytes());

        String requestBody = """
                {
                  "certID": "TP-2026-001",
                  "studentID": "student01",
                  "studentName": "Jane Doe",
                  "courseID": "FSWD-101",
                  "courseName": "Full-Stack Web Dev",
                  "issueDate": "2026-03-06",
                  "expiryDate": "2028-12-31"
                }
                """;

        given()
                .contentType("application/json")
                .body(requestBody)
                .when()
                .post("/api/v1/certificates")
                .then()
                .statusCode(201)
                .body("certID", equalTo("TP-2026-001"))
                .body("orgID", equalTo("techpulse"))
                .body("status", equalTo("ACTIVE"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testIssueCertificateMissingCertID() {
        String requestBody = """
                {
                  "studentID": "student01",
                  "courseID": "FSWD-101"
                }
                """;

        given()
                .contentType("application/json")
                .body(requestBody)
                .when()
                .post("/api/v1/certificates")
                .then()
                .statusCode(400)
                .body("error", containsString("certID is required"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testIssueCertificateMissingStudentID() {
        String requestBody = """
                {
                  "certID": "TP-2026-001",
                  "courseID": "FSWD-101"
                }
                """;

        given()
                .contentType("application/json")
                .body(requestBody)
                .when()
                .post("/api/v1/certificates")
                .then()
                .statusCode(400)
                .body("error", containsString("studentID is required"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testIssueCertificateConflict() throws Exception {
        Mockito.when(fabricClient.submitTransaction(Mockito.eq("IssueCertificate"), Mockito.any(String[].class)))
                .thenThrow(new RuntimeException("Certificate already exists"));

        String requestBody = """
                {
                  "certID": "TP-2026-001",
                  "studentID": "student01",
                  "studentName": "Jane Doe",
                  "courseID": "FSWD-101",
                  "courseName": "Full-Stack Web Dev",
                  "issueDate": "2026-03-06",
                  "expiryDate": "2028-12-31"
                }
                """;

        given()
                .contentType("application/json")
                .body(requestBody)
                .when()
                .post("/api/v1/certificates")
                .then()
                .statusCode(409)
                .body("error", containsString("already exists"));
    }

    // -- Get certificate --

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetCertificate() throws Exception {
        String certJson = sampleCertJson("TP-2026-001", "ACTIVE");
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(certJson.getBytes());

        given()
                .when()
                .get("/api/v1/certificates/{certId}", "TP-2026-001")
                .then()
                .statusCode(200)
                .body("certID", equalTo("TP-2026-001"))
                .body("studentID", equalTo("student01"))
                .body("studentName", equalTo("Jane Doe"))
                .body("orgID", equalTo("techpulse"))
                .body("status", equalTo("ACTIVE"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetCertificateNotFound() throws Exception {
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(new byte[0]);

        given()
                .when()
                .get("/api/v1/certificates/{certId}", "NONEXISTENT")
                .then()
                .statusCode(404)
                .body("error", containsString("not found"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetCertificateForbiddenOtherOrg() throws Exception {
        // Certificate belongs to dataforge, but caller is techpulse
        String certJson = sampleCertJson("DF-2026-001", "ACTIVE")
                .replace("\"orgID\": \"techpulse\"", "\"orgID\": \"dataforge\"");
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(certJson.getBytes());

        given()
                .when()
                .get("/api/v1/certificates/{certId}", "DF-2026-001")
                .then()
                .statusCode(403)
                .body("error", containsString("does not belong to your organization"));
    }

    // -- List certificates --

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testListCertificates() throws Exception {
        String listJson = sampleCertListJson();
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenReturn(listJson.getBytes());

        given()
                .when()
                .get("/api/v1/certificates")
                .then()
                .statusCode(200)
                .header("X-Total-Count", "2")
                .body("$", hasSize(2))
                .body("[0].certID", equalTo("TP-2026-001"))
                .body("[1].certID", equalTo("TP-2026-002"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testListCertificatesEmpty() throws Exception {
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenReturn(new byte[0]);

        given()
                .when()
                .get("/api/v1/certificates")
                .then()
                .statusCode(200)
                .body("$", hasSize(0));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testListCertificatesPagination() throws Exception {
        String listJson = sampleCertListJson();
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificatesByOrg"), Mockito.any(String[].class)))
                .thenReturn(listJson.getBytes());

        given()
                .queryParam("page", 0)
                .queryParam("size", 1)
                .when()
                .get("/api/v1/certificates")
                .then()
                .statusCode(200)
                .header("X-Total-Count", "2")
                .body("$", hasSize(1))
                .body("[0].certID", equalTo("TP-2026-001"));
    }

    // -- Revoke certificate --

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testRevokeCertificate() throws Exception {
        // First call: get cert to verify org ownership
        String activeCertJson = sampleCertJson("TP-2026-001", "ACTIVE");
        String revokedCertJson = sampleCertJson("TP-2026-001", "REVOKED")
                .replace("\"revokeReason\": null", "\"revokeReason\": \"Academic policy violation\"");

        // The resource calls get() twice: once to check ownership, once after revoke
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(activeCertJson.getBytes())
                .thenReturn(revokedCertJson.getBytes());
        Mockito.when(fabricClient.submitTransaction(Mockito.eq("RevokeCertificate"), Mockito.any(String[].class)))
                .thenReturn(new byte[0]);

        given()
                .contentType("application/json")
                .body("""
                        {"reason": "Academic policy violation"}
                        """)
                .when()
                .put("/api/v1/certificates/{certId}/revoke", "TP-2026-001")
                .then()
                .statusCode(200)
                .body("certID", equalTo("TP-2026-001"))
                .body("status", equalTo("REVOKED"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testRevokeCertificateMissingReason() {
        given()
                .contentType("application/json")
                .body("{}")
                .when()
                .put("/api/v1/certificates/{certId}/revoke", "TP-2026-001")
                .then()
                .statusCode(400)
                .body("error", containsString("Revocation reason is required"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testRevokeCertificateAlreadyRevoked() throws Exception {
        String activeCertJson = sampleCertJson("TP-2026-001", "ACTIVE");
        Mockito.when(fabricClient.evaluateTransaction(Mockito.eq("GetCertificate"), Mockito.any(String[].class)))
                .thenReturn(activeCertJson.getBytes());
        Mockito.when(fabricClient.submitTransaction(Mockito.eq("RevokeCertificate"), Mockito.any(String[].class)))
                .thenThrow(new RuntimeException("Certificate is already revoked"));

        given()
                .contentType("application/json")
                .body("""
                        {"reason": "Duplicate revocation attempt"}
                        """)
                .when()
                .put("/api/v1/certificates/{certId}/revoke", "TP-2026-001")
                .then()
                .statusCode(409)
                .body("error", containsString("already revoked"));
    }

    // -- Security: unauthorized --

    @Test
    void testUnauthorizedAccess() {
        given()
                .when()
                .get("/api/v1/certificates")
                .then()
                .statusCode(401);
    }

    @Test
    @TestSecurity(user = "testuser", roles = "viewer")
    void testForbiddenRole() {
        given()
                .when()
                .get("/api/v1/certificates")
                .then()
                .statusCode(403);
    }
}
