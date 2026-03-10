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
class TranscriptResourceTest {

    @InjectMock
    FabricGatewayClient fabricClient;

    private static final String STUDENT_CERTS_JSON = """
            [
                {
                    "certID": "TP-2026-001",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate",
                    "revokeReason": null
                },
                {
                    "certID": "DF-2026-010",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "PostgreSQL Administration",
                    "orgName": "DataForge Institute",
                    "issueDate": "2026-02-20",
                    "expiryDate": "2029-02-20",
                    "grade": "3.8 GPA",
                    "degree": "Associate Certificate",
                    "revokeReason": null
                }
            ]
            """;

    private static final String SINGLE_CERT_JSON = """
            {
                "certID": "TP-2026-001",
                "status": "ACTIVE",
                "studentName": "Jane Doe",
                "courseName": "Full-Stack Web Dev",
                "orgName": "TechPulse Academy",
                "issueDate": "2026-01-15",
                "expiryDate": "2028-12-31",
                "grade": "A",
                "degree": "Professional Certificate",
                "revokeReason": null
            }
            """;

    @BeforeEach
    void resetMocks() throws Exception {
        org.mockito.Mockito.reset(fabricClient);
    }

    @Test
    @TestSecurity(user = "student@techpulse.io", roles = "user")
    void testGetTranscript() throws Exception {
        when(fabricClient.evaluateTransaction(eq("GetCertificatesByStudent"), eq("student@techpulse.io")))
                .thenReturn(STUDENT_CERTS_JSON.getBytes(StandardCharsets.UTF_8));

        given()
            .when()
                .get("/api/v1/transcript")
            .then()
                .statusCode(200)
                .body("$.size()", equalTo(2))
                .body("[0].certID", equalTo("TP-2026-001"))
                .body("[0].status", equalTo("VALID"))
                .body("[0].courseName", equalTo("Full-Stack Web Dev"))
                // Transcript includes private fields
                .body("[0].grade", equalTo("A"))
                .body("[0].degree", equalTo("Professional Certificate"))
                .body("[1].certID", equalTo("DF-2026-010"))
                .body("[1].orgName", equalTo("DataForge Institute"))
                .body("[1].grade", equalTo("3.8 GPA"));
    }

    @Test
    void testGetTranscriptUnauthenticated() {
        // No @TestSecurity — request has no token, should be rejected
        given()
            .when()
                .get("/api/v1/transcript")
            .then()
                .statusCode(401);
    }

    @Test
    @TestSecurity(user = "student@techpulse.io", roles = "user")
    void testGetTranscriptDetail() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(SINGLE_CERT_JSON.getBytes(StandardCharsets.UTF_8));

        given()
            .when()
                .get("/api/v1/transcript/TP-2026-001")
            .then()
                .statusCode(200)
                .body("certID", equalTo("TP-2026-001"))
                .body("status", equalTo("VALID"))
                .body("studentName", equalTo("Jane Doe"))
                .body("courseName", equalTo("Full-Stack Web Dev"))
                .body("orgName", equalTo("TechPulse Academy"))
                // Transcript detail includes private fields
                .body("grade", equalTo("A"))
                .body("degree", equalTo("Professional Certificate"));
    }

    @Test
    @TestSecurity(user = "student@techpulse.io", roles = "user")
    void testGetTranscriptDetailNotFound() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("NONEXISTENT")))
                .thenThrow(new RuntimeException("Certificate not found: NONEXISTENT"));

        given()
            .when()
                .get("/api/v1/transcript/NONEXISTENT")
            .then()
                .statusCode(404)
                .body("certID", equalTo("NONEXISTENT"))
                .body("status", equalTo("NOT_FOUND"));
    }

    @Test
    @TestSecurity(user = "student@techpulse.io", roles = "user")
    void testGetTranscriptEmptyResult() throws Exception {
        when(fabricClient.evaluateTransaction(eq("GetCertificatesByStudent"), eq("student@techpulse.io")))
                .thenReturn("[]".getBytes(StandardCharsets.UTF_8));

        given()
            .when()
                .get("/api/v1/transcript")
            .then()
                .statusCode(200)
                .body("$.size()", equalTo(0));
    }

    @Test
    void testGetTranscriptDetailUnauthenticated() {
        given()
            .when()
                .get("/api/v1/transcript/TP-2026-001")
            .then()
                .statusCode(401);
    }
}
