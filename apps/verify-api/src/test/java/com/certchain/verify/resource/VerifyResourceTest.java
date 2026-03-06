package com.certchain.verify.resource;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.certchain.verify.client.FabricGatewayClient;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;

@QuarkusTest
@TestSecurity(authorizationEnabled = false)
class VerifyResourceTest {

    @InjectMock
    FabricGatewayClient fabricClient;

    private static final String ACTIVE_CERT_JSON = """
            {
                "certID": "TP-2026-001",
                "status": "ACTIVE",
                "studentName": "Jane Doe",
                "courseName": "Full-Stack Web Dev",
                "orgName": "TechPulse Academy",
                "issueDate": "2026-01-15",
                "expiryDate": "2028-12-31",
                "revokeReason": null
            }
            """;

    private static final String REVOKED_CERT_JSON = """
            {
                "certID": "TP-2026-002",
                "status": "REVOKED",
                "studentName": "John Smith",
                "courseName": "Cloud-Native Microservices",
                "orgName": "TechPulse Academy",
                "issueDate": "2025-09-01",
                "expiryDate": "2027-09-01",
                "revokeReason": "Academic misconduct"
            }
            """;

    @BeforeEach
    void resetMocks() throws Exception {
        // Reset to a clean state before each test
        org.mockito.Mockito.reset(fabricClient);
    }

    @Test
    void testVerifyCertificateValid() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(ACTIVE_CERT_JSON.getBytes(StandardCharsets.UTF_8));

        given()
            .when()
                .get("/api/v1/verify/TP-2026-001")
            .then()
                .statusCode(200)
                .body("certID", equalTo("TP-2026-001"))
                .body("status", equalTo("VALID"))
                .body("studentName", equalTo("Jane Doe"))
                .body("courseName", equalTo("Full-Stack Web Dev"))
                .body("orgName", equalTo("TechPulse Academy"))
                .body("issueDate", equalTo("2026-01-15"))
                .body("expiryDate", equalTo("2028-12-31"))
                .body("verifiedAt", notNullValue());
    }

    @Test
    void testVerifyCertificateRevoked() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-002")))
                .thenReturn(REVOKED_CERT_JSON.getBytes(StandardCharsets.UTF_8));

        given()
            .when()
                .get("/api/v1/verify/TP-2026-002")
            .then()
                .statusCode(200)
                .body("certID", equalTo("TP-2026-002"))
                .body("status", equalTo("REVOKED"))
                .body("studentName", equalTo("John Smith"))
                .body("revokeReason", equalTo("Academic misconduct"));
    }

    @Test
    void testVerifyCertificateNotFound() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("NONEXISTENT")))
                .thenThrow(new RuntimeException("Certificate not found: NONEXISTENT"));

        given()
            .when()
                .get("/api/v1/verify/NONEXISTENT")
            .then()
                .statusCode(404)
                .body("certID", equalTo("NONEXISTENT"))
                .body("status", equalTo("NOT_FOUND"));
    }

    @Test
    void testVerifyQRCode() throws Exception {
        // QR code generation does not call Fabric — it only needs the certId and base URL.
        // No mock setup needed for this endpoint.
        given()
            .when()
                .get("/api/v1/verify/TP-2026-001/qr")
            .then()
                .statusCode(200)
                .contentType("image/png")
                .body(notNullValue());
    }

    @Test
    void testBatchVerify() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(ACTIVE_CERT_JSON.getBytes(StandardCharsets.UTF_8));
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-002")))
                .thenReturn(REVOKED_CERT_JSON.getBytes(StandardCharsets.UTF_8));

        given()
                .queryParam("ids", "TP-2026-001,TP-2026-002")
            .when()
                .get("/api/v1/verify/batch")
            .then()
                .statusCode(200)
                .body("$.size()", equalTo(2))
                .body("[0].certID", equalTo("TP-2026-001"))
                .body("[0].status", equalTo("VALID"))
                .body("[1].certID", equalTo("TP-2026-002"))
                .body("[1].status", equalTo("REVOKED"));
    }

    @Test
    void testBatchVerifyWithNotFound() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(ACTIVE_CERT_JSON.getBytes(StandardCharsets.UTF_8));
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("MISSING")))
                .thenThrow(new RuntimeException("Certificate not found: MISSING"));

        given()
                .queryParam("ids", "TP-2026-001,MISSING")
            .when()
                .get("/api/v1/verify/batch")
            .then()
                .statusCode(200)
                .body("$.size()", equalTo(2))
                .body("[0].status", equalTo("VALID"))
                .body("[1].certID", equalTo("MISSING"))
                .body("[1].status", equalTo("NOT_FOUND"));
    }

    @Test
    void testBatchVerifyMissingIds() {
        given()
            .when()
                .get("/api/v1/verify/batch")
            .then()
                .statusCode(400)
                .body("error", containsString("ids"));
    }

    @Test
    void testBatchVerifyEmptyIds() {
        given()
                .queryParam("ids", "  ,  , ")
            .when()
                .get("/api/v1/verify/batch")
            .then()
                .statusCode(400)
                .body("error", containsString("No valid"));
    }
}
