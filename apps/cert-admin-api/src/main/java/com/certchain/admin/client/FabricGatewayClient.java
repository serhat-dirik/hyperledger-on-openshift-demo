package com.certchain.admin.client;

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

import org.hyperledger.fabric.client.CommitException;
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
 * Hyperledger Fabric Gateway SDK wrapper.
 * Manages connection lifecycle and transaction submission/evaluation.
 *
 * Config properties:
 *   certchain.fabric.channel, certchain.fabric.chaincode,
 *   certchain.fabric.peer-endpoint, certchain.fabric.msp-id,
 *   certchain.fabric.cert-path, certchain.fabric.key-path,
 *   certchain.fabric.tls-cert-path
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
                    .endorseOptions(options -> options.withDeadlineAfter(15, TimeUnit.SECONDS))
                    .submitOptions(options -> options.withDeadlineAfter(5, TimeUnit.SECONDS))
                    .commitStatusOptions(options -> options.withDeadlineAfter(1, TimeUnit.MINUTES))
                    .connect();

            Network network = gateway.getNetwork(channelName);
            contract = network.getContract(chaincodeName);

            LOG.infof("Fabric Gateway connected: channel=%s, chaincode=%s, peer=%s, msp=%s",
                    channelName, chaincodeName, peerEndpoint, mspId);
        } catch (Exception e) {
            LOG.error("Failed to initialize Fabric Gateway connection", e);
            throw new RuntimeException("Failed to initialize Fabric Gateway", e);
        }
    }

    @PreDestroy
    void shutdown() {
        try {
            if (gateway != null) {
                gateway.close();
                LOG.info("Fabric Gateway closed");
            }
        } finally {
            if (grpcChannel != null) {
                try {
                    grpcChannel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
                    LOG.info("gRPC channel shut down");
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    LOG.warn("Interrupted while shutting down gRPC channel", e);
                }
            }
        }
    }

    /**
     * Submit a transaction to the ledger (write operation).
     * The transaction is endorsed, ordered, and committed.
     */
    public byte[] submitTransaction(String name, String... args) throws GatewayException, CommitException {
        LOG.debugf("submitTransaction: %s(%s)", name, String.join(", ", args));
        try {
            return contract.submitTransaction(name, args);
        } catch (Exception e) {
            LOG.errorf(e, "Failed to submit transaction: %s", name);
            throw e;
        }
    }

    /**
     * Evaluate a transaction against the ledger (read-only query).
     * The transaction is evaluated on endorsing peers without being committed.
     */
    public byte[] evaluateTransaction(String name, String... args) throws GatewayException {
        LOG.debugf("evaluateTransaction: %s(%s)", name, String.join(", ", args));
        try {
            return contract.evaluateTransaction(name, args);
        } catch (Exception e) {
            LOG.errorf(e, "Failed to evaluate transaction: %s", name);
            throw e;
        }
    }

    private Identity createIdentity() throws IOException, CertificateException {
        Path certificatePath = Path.of(certPath);
        try (Reader certReader = Files.newBufferedReader(certificatePath)) {
            X509Certificate certificate = Identities.readX509Certificate(certReader);
            return new X509Identity(mspId, certificate);
        }
    }

    private Signer createSigner() throws IOException, InvalidKeyException {
        Path privateKeyPath = Path.of(keyPath);
        try (Reader keyReader = Files.newBufferedReader(privateKeyPath)) {
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

        // Parse host and port from endpoint (e.g., "peer0-techpulse:7051")
        String host = peerEndpoint;
        if (peerEndpoint.contains(":")) {
            host = peerEndpoint.substring(0, peerEndpoint.indexOf(':'));
        }

        return Grpc.newChannelBuilder(peerEndpoint, credentials)
                .overrideAuthority(host)
                .build();
    }
}
