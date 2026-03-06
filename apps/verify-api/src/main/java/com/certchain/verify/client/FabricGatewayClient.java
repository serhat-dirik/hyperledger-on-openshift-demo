package com.certchain.verify.client;

import java.io.IOException;
import java.io.Reader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.InvalidKeyException;
import java.security.PrivateKey;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.concurrent.TimeUnit;

import io.grpc.ChannelCredentials;
import io.grpc.Grpc;
import io.grpc.InsecureChannelCredentials;
import io.grpc.ManagedChannel;
import io.grpc.TlsChannelCredentials;

import org.hyperledger.fabric.client.Contract;
import org.hyperledger.fabric.client.Gateway;
import org.hyperledger.fabric.client.GatewayException;
import org.hyperledger.fabric.client.Network;
import org.hyperledger.fabric.client.identity.Identities;
import org.hyperledger.fabric.client.identity.Identity;
import org.hyperledger.fabric.client.identity.Signer;
import org.hyperledger.fabric.client.identity.Signers;
import org.hyperledger.fabric.client.identity.X509Identity;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.context.ApplicationScoped;

import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Fabric Gateway client for the verification service.
 * Read-only: only evaluateTransaction() calls, no submits.
 */
@ApplicationScoped
public class FabricGatewayClient {

    private static final Logger LOG = Logger.getLogger(FabricGatewayClient.class);

    @ConfigProperty(name = "certchain.fabric.channel")
    String channelName;

    @ConfigProperty(name = "certchain.fabric.chaincode")
    String chaincodeName;

    @ConfigProperty(name = "certchain.fabric.peer-endpoint")
    String peerEndpoint;

    @ConfigProperty(name = "certchain.fabric.msp-id")
    String mspId;

    @ConfigProperty(name = "certchain.fabric.cert-path")
    String certPath;

    @ConfigProperty(name = "certchain.fabric.key-path")
    String keyPath;

    @ConfigProperty(name = "certchain.fabric.tls-cert-path")
    String tlsCertPath;

    private ManagedChannel grpcChannel;
    private Gateway gateway;
    private Contract contract;

    @PostConstruct
    void init() {
        try {
            Identity identity = createIdentity();
            Signer signer = createSigner();

            grpcChannel = createGrpcChannel();

            gateway = Gateway.newInstance()
                    .identity(identity)
                    .signer(signer)
                    .connection(grpcChannel)
                    .evaluateOptions(options -> options.withDeadlineAfter(5, TimeUnit.SECONDS))
                    .connect();

            Network network = gateway.getNetwork(channelName);
            contract = network.getContract(chaincodeName);

            LOG.infof("Fabric Gateway connected: channel=%s, chaincode=%s, peer=%s",
                    channelName, chaincodeName, peerEndpoint);
        } catch (Exception e) {
            LOG.errorf(e, "Failed to initialize Fabric Gateway connection");
            throw new RuntimeException("Fabric Gateway initialization failed", e);
        }
    }

    @PreDestroy
    void shutdown() {
        try {
            if (gateway != null) {
                gateway.close();
            }
        } finally {
            if (grpcChannel != null) {
                try {
                    grpcChannel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
        }
        LOG.info("Fabric Gateway connection closed");
    }

    public byte[] evaluateTransaction(String name, String... args) throws GatewayException {
        return contract.evaluateTransaction(name, args);
    }

    private Identity createIdentity() throws IOException, CertificateException {
        try (Reader certReader = Files.newBufferedReader(Path.of(certPath))) {
            X509Certificate certificate = Identities.readX509Certificate(certReader);
            return new X509Identity(mspId, certificate);
        }
    }

    private Signer createSigner() throws IOException, InvalidKeyException {
        try (Reader keyReader = Files.newBufferedReader(Path.of(keyPath))) {
            PrivateKey privateKey = Identities.readPrivateKey(keyReader);
            return Signers.newPrivateKeySigner(privateKey);
        }
    }

    private ManagedChannel createGrpcChannel() throws IOException, CertificateException {
        ChannelCredentials credentials;

        Path tlsPath = Path.of(tlsCertPath);
        if (Files.exists(tlsPath)) {
            credentials = TlsChannelCredentials.newBuilder()
                    .trustManager(Files.newInputStream(tlsPath))
                    .build();
            LOG.infof("Using TLS for peer connection: %s", peerEndpoint);
        } else {
            credentials = InsecureChannelCredentials.create();
            LOG.warnf("TLS cert not found at %s — using insecure connection to %s", tlsCertPath, peerEndpoint);
        }

        String host = peerEndpoint;
        if (peerEndpoint.contains(":")) {
            host = peerEndpoint.substring(0, peerEndpoint.indexOf(':'));
        }

        return Grpc.newChannelBuilder(peerEndpoint, credentials)
                .overrideAuthority(host)
                .build();
    }
}
