package com.certchain.admin.model;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Data transfer object for a course offered by a training institute.
 */
@Schema(description = "Course offered by a training institute")
public record CourseDTO(
    @Schema(description = "Course identifier", example = "FSWD-101")
    String courseID,
    @Schema(description = "Course display name", example = "Full-Stack Web Dev")
    String courseName
) {}
