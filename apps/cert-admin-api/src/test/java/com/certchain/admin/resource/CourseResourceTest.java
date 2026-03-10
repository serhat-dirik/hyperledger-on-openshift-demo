package com.certchain.admin.resource;

import com.certchain.admin.client.FabricGatewayClient;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.quarkus.test.security.oidc.Claim;
import io.quarkus.test.security.oidc.OidcSecurity;

import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

@QuarkusTest
class CourseResourceTest {

    // Mock FabricGatewayClient to prevent @PostConstruct from connecting to a real peer
    @InjectMock
    FabricGatewayClient fabricClient;

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "techpulse")
    })
    void testGetCoursesTechPulse() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(200)
                .body("$", hasSize(3))
                .body("courseID", hasItems("FSWD-101", "CNM-201", "DSO-301"))
                .body("courseName", hasItems("Full-Stack Web Dev", "Cloud-Native Microservices", "DevSecOps Fundamentals"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "dataforge")
    })
    void testGetCoursesDataForge() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(200)
                .body("$", hasSize(3))
                .body("courseID", hasItems("PGA-101", "DPE-201", "GDB-301"))
                .body("courseName", hasItems("PostgreSQL Administration", "Data Pipeline Engineering", "Graph Databases Masterclass"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "neuralpath")
    })
    void testGetCoursesNeuralPath() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(200)
                .body("$", hasSize(3))
                .body("courseID", hasItems("AML-101", "LFT-201", "CVP-301"))
                .body("courseName", hasItems("Applied Machine Learning", "LLM Fine-Tuning Workshop", "Computer Vision Practicum"));
    }

    @Test
    @TestSecurity(user = "testuser", roles = "org-admin")
    @OidcSecurity(claims = {
            @Claim(key = "org_id", value = "unknown-org")
    })
    void testGetCoursesUnknownOrg() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(200)
                .body("$", hasSize(0));
    }

    @Test
    void testGetCoursesUnauthorized() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(401);
    }

    @Test
    @TestSecurity(user = "testuser", roles = "viewer")
    void testGetCoursesForbiddenRole() {
        given()
                .when()
                .get("/api/v1/courses")
                .then()
                .statusCode(403);
    }
}
