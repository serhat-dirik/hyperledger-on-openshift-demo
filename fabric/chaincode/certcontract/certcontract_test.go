package certcontract_test

import (
	"encoding/json"
	"testing"

	"github.com/certchain/certcontract"
	"github.com/hyperledger/fabric-chaincode-go/v2/shim"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"github.com/hyperledger/fabric-protos-go-apiv2/ledger/queryresult"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// --- Mock Stub ---

type MockStub struct {
	mock.Mock
	shim.ChaincodeStubInterface
	state map[string][]byte
}

func NewMockStub() *MockStub {
	return &MockStub{state: make(map[string][]byte)}
}

func (m *MockStub) GetTxID() string {
	return "mock-tx-id-001"
}

func (m *MockStub) CreateCompositeKey(objectType string, attributes []string) (string, error) {
	key := objectType
	for _, attr := range attributes {
		key += "\x00" + attr
	}
	key += "\x00"
	return key, nil
}

func (m *MockStub) GetState(key string) ([]byte, error) {
	return m.state[key], nil
}

func (m *MockStub) PutState(key string, value []byte) error {
	m.state[key] = value
	return nil
}

func (m *MockStub) GetQueryResult(query string) (shim.StateQueryIteratorInterface, error) {
	args := m.Called(query)
	return args.Get(0).(shim.StateQueryIteratorInterface), args.Error(1)
}

func (m *MockStub) GetStateByPartialCompositeKey(objectType string, attributes []string) (shim.StateQueryIteratorInterface, error) {
	args := m.Called(objectType, attributes)
	return args.Get(0).(shim.StateQueryIteratorInterface), args.Error(1)
}

func (m *MockStub) GetHistoryForKey(key string) (shim.HistoryQueryIteratorInterface, error) {
	args := m.Called(key)
	return args.Get(0).(shim.HistoryQueryIteratorInterface), args.Error(1)
}

// --- Mock Iterator ---

type MockIterator struct {
	records []*queryresult.KV
	index   int
}

func NewMockIterator(records []*queryresult.KV) *MockIterator {
	return &MockIterator{records: records}
}

func (m *MockIterator) HasNext() bool {
	return m.index < len(m.records)
}

func (m *MockIterator) Next() (*queryresult.KV, error) {
	if m.index >= len(m.records) {
		return nil, nil
	}
	record := m.records[m.index]
	m.index++
	return record, nil
}

func (m *MockIterator) Close() error {
	return nil
}

// --- Mock History Iterator ---

type MockHistoryIterator struct {
	records []*queryresult.KeyModification
	index   int
}

func (m *MockHistoryIterator) HasNext() bool {
	return m.index < len(m.records)
}

func (m *MockHistoryIterator) Next() (*queryresult.KeyModification, error) {
	if m.index >= len(m.records) {
		return nil, nil
	}
	record := m.records[m.index]
	m.index++
	return record, nil
}

func (m *MockHistoryIterator) Close() error {
	return nil
}

// --- Mock Transaction Context ---

type MockTransactionContext struct {
	contractapi.TransactionContext
	stub *MockStub
}

func (m *MockTransactionContext) GetStub() shim.ChaincodeStubInterface {
	return m.stub
}

// --- Helper ---

func newTestContext() (*certcontract.CertContract, *MockTransactionContext, *MockStub) {
	cc := new(certcontract.CertContract)
	stub := NewMockStub()
	ctx := &MockTransactionContext{stub: stub}
	return cc, ctx, stub
}

func issueSampleCert(t *testing.T, cc *certcontract.CertContract, ctx *MockTransactionContext) {
	t.Helper()
	err := cc.IssueCertificate(ctx,
		"TP-FSWD-001", "student01@techpulse.demo", "Alice Chen",
		"FSWD-101", "Full-Stack Web Dev",
		"techpulse", "TechPulse Academy",
		"2026-01-15", "2028-01-15", "A", "Professional Certificate", "")
	assert.NoError(t, err)
}

// --- Tests ---

func TestIssueCertificate_HappyPath(t *testing.T) {
	cc, ctx, stub := newTestContext()

	err := cc.IssueCertificate(ctx,
		"TP-FSWD-001", "student01@techpulse.demo", "Alice Chen",
		"FSWD-101", "Full-Stack Web Dev",
		"techpulse", "TechPulse Academy",
		"2026-01-15", "2028-01-15", "A", "Professional Certificate", "")
	assert.NoError(t, err)

	certJSON := stub.state["TP-FSWD-001"]
	assert.NotNil(t, certJSON)

	var cert certcontract.Certificate
	err = json.Unmarshal(certJSON, &cert)
	assert.NoError(t, err)
	assert.Equal(t, "ACTIVE", cert.Status)
	assert.Equal(t, "certificate", cert.DocType)
	assert.Equal(t, "Alice Chen", cert.StudentName)
	assert.Equal(t, "techpulse", cert.OrgID)
	assert.Equal(t, "A", cert.Grade)
	assert.Equal(t, "Professional Certificate", cert.Degree)
}

func TestIssueCertificate_Duplicate(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	err := cc.IssueCertificate(ctx,
		"TP-FSWD-001", "student02@techpulse.demo", "Bob Smith",
		"FSWD-101", "Full-Stack Web Dev",
		"techpulse", "TechPulse Academy",
		"2026-01-15", "2028-01-15", "B", "", "")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")
}

func TestIssueCertificate_MissingFields(t *testing.T) {
	cc, ctx, _ := newTestContext()

	err := cc.IssueCertificate(ctx,
		"", "student01@techpulse.demo", "Alice Chen",
		"FSWD-101", "Full-Stack Web Dev",
		"techpulse", "TechPulse Academy",
		"2026-01-15", "2028-01-15", "", "", "")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "required")
}

func TestGetCertificate_Found(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	cert, err := cc.GetCertificate(ctx, "TP-FSWD-001")
	assert.NoError(t, err)
	assert.Equal(t, "TP-FSWD-001", cert.CertID)
	assert.Equal(t, "ACTIVE", cert.Status)
}

func TestGetCertificate_NotFound(t *testing.T) {
	cc, ctx, _ := newTestContext()

	cert, err := cc.GetCertificate(ctx, "NONEXISTENT")
	assert.Error(t, err)
	assert.Nil(t, cert)
	assert.Contains(t, err.Error(), "not found")
}

func TestVerifyCertificate_Active(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	cert, err := cc.VerifyCertificate(ctx, "TP-FSWD-001")
	assert.NoError(t, err)
	assert.Equal(t, "ACTIVE", cert.Status)
}

func TestVerifyCertificate_Expired(t *testing.T) {
	cc, ctx, _ := newTestContext()

	err := cc.IssueCertificate(ctx,
		"TP-OLD-001", "student01@techpulse.demo", "Alice Chen",
		"FSWD-101", "Full-Stack Web Dev",
		"techpulse", "TechPulse Academy",
		"2020-01-15", "2022-01-15", "B+", "", "")
	assert.NoError(t, err)

	cert, err := cc.VerifyCertificate(ctx, "TP-OLD-001")
	assert.NoError(t, err)
	assert.Equal(t, "EXPIRED", cert.Status)
}

func TestRevokeCertificate_HappyPath(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	err := cc.RevokeCertificate(ctx, "TP-FSWD-001", "Academic misconduct")
	assert.NoError(t, err)

	cert, err := cc.GetCertificate(ctx, "TP-FSWD-001")
	assert.NoError(t, err)
	assert.Equal(t, "REVOKED", cert.Status)
	assert.Equal(t, "Academic misconduct", cert.RevokeReason)
}

func TestRevokeCertificate_AlreadyRevoked(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	err := cc.RevokeCertificate(ctx, "TP-FSWD-001", "reason1")
	assert.NoError(t, err)

	err = cc.RevokeCertificate(ctx, "TP-FSWD-001", "reason2")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already revoked")
}

func TestRevokeCertificate_NotFound(t *testing.T) {
	cc, ctx, _ := newTestContext()

	err := cc.RevokeCertificate(ctx, "NONEXISTENT", "reason")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

func TestUpdateCertificate_HappyPath(t *testing.T) {
	cc, ctx, _ := newTestContext()
	issueSampleCert(t, cc, ctx)

	err := cc.UpdateCertificate(ctx, "TP-FSWD-001", "A+", "Master Certificate")
	assert.NoError(t, err)

	cert, err := cc.GetCertificate(ctx, "TP-FSWD-001")
	assert.NoError(t, err)
	assert.Equal(t, "A+", cert.Grade)
	assert.Equal(t, "Master Certificate", cert.Degree)
	assert.Equal(t, "ACTIVE", cert.Status) // status unchanged
}

func TestUpdateCertificate_NotFound(t *testing.T) {
	cc, ctx, _ := newTestContext()

	err := cc.UpdateCertificate(ctx, "NONEXISTENT", "A", "Cert")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

func TestGetCertificatesByStudent(t *testing.T) {
	cc, ctx, stub := newTestContext()
	issueSampleCert(t, cc, ctx)

	certJSON := stub.state["TP-FSWD-001"]
	iter := NewMockIterator([]*queryresult.KV{
		{Key: "TP-FSWD-001", Value: certJSON},
	})
	stub.On("GetQueryResult", mock.Anything).Return(iter, nil)

	certs, err := cc.GetCertificatesByStudent(ctx, "student01@techpulse.demo")
	assert.NoError(t, err)
	assert.Len(t, certs, 1)
	assert.Equal(t, "Alice Chen", certs[0].StudentName)
	assert.Equal(t, "A", certs[0].Grade)
	assert.Equal(t, "Professional Certificate", certs[0].Degree)
}

func TestGetCertificatesByStudent_NoCerts(t *testing.T) {
	cc, ctx, stub := newTestContext()

	iter := NewMockIterator([]*queryresult.KV{})
	stub.On("GetQueryResult", mock.Anything).Return(iter, nil)

	certs, err := cc.GetCertificatesByStudent(ctx, "unknown-student")
	assert.NoError(t, err)
	assert.Empty(t, certs)
}

func TestGetCertificatesByOrg(t *testing.T) {
	cc, ctx, stub := newTestContext()
	issueSampleCert(t, cc, ctx)

	certJSON := stub.state["TP-FSWD-001"]
	iter := NewMockIterator([]*queryresult.KV{
		{Key: "CERT\x00techpulse\x00TP-FSWD-001\x00", Value: certJSON},
	})
	stub.On("GetStateByPartialCompositeKey", "CERT", []string{"techpulse"}).Return(iter, nil)

	certs, err := cc.GetCertificatesByOrg(ctx, "techpulse")
	assert.NoError(t, err)
	assert.Len(t, certs, 1)
	assert.Equal(t, "techpulse", certs[0].OrgID)
}

func TestGetCertificateHistory(t *testing.T) {
	cc, ctx, stub := newTestContext()
	issueSampleCert(t, cc, ctx)

	certJSON := stub.state["TP-FSWD-001"]
	histIter := &MockHistoryIterator{
		records: []*queryresult.KeyModification{
			{
				TxId:      "tx-001",
				Value:     certJSON,
				Timestamp: timestamppb.Now(),
				IsDelete:  false,
			},
		},
	}
	stub.On("GetHistoryForKey", "TP-FSWD-001").Return(histIter, nil)

	historyJSON, err := cc.GetCertificateHistory(ctx, "TP-FSWD-001")
	assert.NoError(t, err)
	assert.NotEmpty(t, historyJSON)

	var history []certcontract.HistoryEntry
	err = json.Unmarshal([]byte(historyJSON), &history)
	assert.NoError(t, err)
	assert.Len(t, history, 1)
	assert.Equal(t, "tx-001", history[0].TxID)
}

func TestInitLedger(t *testing.T) {
	cc, ctx, stub := newTestContext()

	err := cc.InitLedger(ctx)
	assert.NoError(t, err)

	assert.NotNil(t, stub.state["TP-FSWD-001"])
	assert.NotNil(t, stub.state["DF-PGA-001"])
	assert.NotNil(t, stub.state["NP-AML-001"])

	var cert certcontract.Certificate
	_ = json.Unmarshal(stub.state["DF-PGA-001"], &cert)
	assert.Equal(t, "dataforge", cert.OrgID)
	assert.Equal(t, "Carol Wang", cert.StudentName)
	assert.NotEmpty(t, cert.Grade)
	assert.NotEmpty(t, cert.Degree)
}
