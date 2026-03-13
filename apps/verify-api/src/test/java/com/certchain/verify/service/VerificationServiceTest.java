package com.certchain.verify.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.certchain.verify.client.FabricGatewayClient;
import com.certchain.verify.model.VerificationResult;
import com.certchain.verify.service.VerificationService.CertificateNotFoundException;
import com.certchain.verify.service.VerificationService.VerificationException;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

@QuarkusTest
class VerificationServiceTest {

    @Inject
    VerificationService verificationService;

    @InjectMock
    FabricGatewayClient fabricClient;

    @BeforeEach
    void resetMocks() throws Exception {
        org.mockito.Mockito.reset(fabricClient);
    }

    @Test
    void testVerifyActiveReturnsValid() throws Exception {
        String json = """
                {
                    "certID": "TP-2026-001",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verify("TP-2026-001");

        assertEquals("TP-2026-001", result.certID());
        assertEquals("VALID", result.status());
        assertEquals("Jane Doe", result.studentName());
        assertEquals("Full-Stack Web Dev", result.courseName());
        assertEquals("TechPulse Academy", result.orgName());
        assertNotNull(result.verifiedAt());
        // Public verify hides private fields
        assertNull(result.grade());
        assertNull(result.degree());
    }

    @Test
    void testVerifyRevokedReturnsRevoked() throws Exception {
        String json = """
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
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-002")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verify("TP-2026-002");

        assertEquals("TP-2026-002", result.certID());
        assertEquals("REVOKED", result.status());
        assertEquals("Academic misconduct", result.revokeReason());
    }

    @Test
    void testVerifyExpiredReturnsExpired() throws Exception {
        String json = """
                {
                    "certID": "NP-2024-005",
                    "status": "EXPIRED",
                    "studentName": "Alice Wong",
                    "courseName": "Applied Machine Learning",
                    "orgName": "NeuralPath Labs",
                    "issueDate": "2024-01-10",
                    "expiryDate": "2025-01-10"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("NP-2024-005")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verify("NP-2024-005");

        assertEquals("NP-2024-005", result.certID());
        assertEquals("EXPIRED", result.status());
        assertEquals("NeuralPath Labs", result.orgName());
    }

    @Test
    void testVerifyNotFoundThrowsException() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("NONEXISTENT")))
                .thenThrow(new RuntimeException("Certificate not found: NONEXISTENT"));

        CertificateNotFoundException ex = assertThrows(
                CertificateNotFoundException.class,
                () -> verificationService.verify("NONEXISTENT")
        );
        assertEquals("NONEXISTENT", ex.getCertId());
    }

    @Test
    void testVerifyFabricErrorThrowsVerificationException() throws Exception {
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenThrow(new RuntimeException("gRPC connection timeout"));

        assertThrows(
                VerificationException.class,
                () -> verificationService.verify("TP-2026-001")
        );
    }

    @Test
    void testGetCertificatesByStudent() throws Exception {
        String json = """
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
                        "degree": "Professional Certificate"
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
                        "degree": "Associate Certificate"
                    }
                ]
                """;
        when(fabricClient.evaluateTransaction(eq("GetCertificatesByStudent"), eq("jane@example.com")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        List<VerificationResult> results = verificationService.getCertificatesByStudent("jane@example.com");

        assertEquals(2, results.size());
        assertEquals("TP-2026-001", results.get(0).certID());
        assertEquals("VALID", results.get(0).status());
        // Transcript includes private fields
        assertEquals("A", results.get(0).grade());
        assertEquals("Professional Certificate", results.get(0).degree());
        assertEquals("DF-2026-010", results.get(1).certID());
        assertEquals("DataForge Institute", results.get(1).orgName());
        assertEquals("3.8 GPA", results.get(1).grade());
    }

    @Test
    void testBatchVerifyMixed() throws Exception {
        String activeJson = """
                {
                    "certID": "TP-2026-001",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(activeJson.getBytes(StandardCharsets.UTF_8));
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("MISSING")))
                .thenThrow(new RuntimeException("Certificate not found: MISSING"));

        List<VerificationResult> results = verificationService.batchVerify(List.of("TP-2026-001", "MISSING"));

        assertEquals(2, results.size());
        assertEquals("VALID", results.get(0).status());
        assertEquals("NOT_FOUND", results.get(1).status());
        assertEquals("MISSING", results.get(1).certID());
    }

    @Test
    void testVerifyFullIncludesPrivateFields() throws Exception {
        String json = """
                {
                    "certID": "TP-2026-001",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verifyFull("TP-2026-001");

        assertEquals("TP-2026-001", result.certID());
        assertEquals("VALID", result.status());
        // verifyFull includes private fields
        assertEquals("A", result.grade());
        assertEquals("Professional Certificate", result.degree());
    }

    @Test
    void testVerifyForStudentOwnerIncludesPrivateFields() throws Exception {
        String json = """
                {
                    "certID": "TP-2026-001",
                    "studentID": "jane@example.com",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verifyForStudent("TP-2026-001", "jane@example.com");

        assertEquals("TP-2026-001", result.certID());
        assertEquals("VALID", result.status());
        // Owner sees private fields
        assertEquals("A", result.grade());
        assertEquals("Professional Certificate", result.degree());
    }

    @Test
    void testVerifyForStudentNonOwnerHidesPrivateFields() throws Exception {
        String json = """
                {
                    "certID": "TP-2026-001",
                    "studentID": "jane@example.com",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verifyForStudent("TP-2026-001", "other@example.com");

        assertEquals("TP-2026-001", result.certID());
        assertEquals("VALID", result.status());
        assertEquals("Jane Doe", result.studentName());
        // Non-owner does NOT see private fields
        assertNull(result.grade());
        assertNull(result.degree());
    }

    @Test
    void testVerifyForStudentPrefixMatchIncludesPrivateFields() throws Exception {
        // Tests backward compatibility: ledger has short-form studentID ("jane")
        // but JWT provides full email ("jane@example.com")
        String json = """
                {
                    "certID": "TP-2026-001",
                    "studentID": "jane",
                    "status": "ACTIVE",
                    "studentName": "Jane Doe",
                    "courseName": "Full-Stack Web Dev",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-15",
                    "expiryDate": "2028-12-31",
                    "grade": "A",
                    "degree": "Professional Certificate"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-001")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verifyForStudent("TP-2026-001", "jane@example.com");

        assertEquals("TP-2026-001", result.certID());
        assertEquals("VALID", result.status());
        // Prefix match: "jane" == username part of "jane@example.com"
        assertEquals("A", result.grade());
        assertEquals("Professional Certificate", result.degree());
    }

    @Test
    void testUnknownStatusMapsToUnknown() throws Exception {
        String json = """
                {
                    "certID": "TP-2026-099",
                    "status": "SUSPENDED",
                    "studentName": "Test User",
                    "courseName": "Test Course",
                    "orgName": "TechPulse Academy",
                    "issueDate": "2026-01-01",
                    "expiryDate": "2027-01-01"
                }
                """;
        when(fabricClient.evaluateTransaction(eq("VerifyCertificate"), eq("TP-2026-099")))
                .thenReturn(json.getBytes(StandardCharsets.UTF_8));

        VerificationResult result = verificationService.verify("TP-2026-099");

        assertEquals("UNKNOWN", result.status());
    }
}
