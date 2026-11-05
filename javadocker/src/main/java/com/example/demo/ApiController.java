package com.example.demo;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Exposes build/runtime metadata so an artifact built and published to Nexus can be
 * verified end-to-end at runtime (build -> deploy to Nexus -> run -> hit this endpoint).
 * Also logs via log4j-core so the dependency pulled in for the Nexus vulnerability
 * scanning showcase is actually exercised at runtime, not just declared in the POM.
 */
@RestController
public class ApiController {

    private static final Logger logger = LogManager.getLogger(ApiController.class);

    @GetMapping("/api/info")
    public Map<String, String> info() {
        logger.info("Serving /api/info request");

        Map<String, String> payload = new LinkedHashMap<>();
        payload.put("application", "javadocker-sample");
        payload.put("version", "1.0.0");
        payload.put("deploymentColor", System.getenv().getOrDefault("APP_COLOR", "unknown"));
        payload.put("deploymentTag", System.getenv().getOrDefault("APP_TAG", "n/a"));
        payload.put("timestamp", Instant.now().toString());
        return payload;
    }
}
