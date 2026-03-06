package certcontract

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// Certificate represents a course completion credential on the ledger.
type Certificate struct {
	DocType      string `json:"docType"`
	CertID       string `json:"certID"`
	StudentID    string `json:"studentID"`
	StudentName  string `json:"studentName"`
	CourseID     string `json:"courseID"`
	CourseName   string `json:"courseName"`
	OrgID        string `json:"orgID"`
	OrgName      string `json:"orgName"`
	IssueDate    string `json:"issueDate"`
	ExpiryDate   string `json:"expiryDate"`
	Status       string `json:"status"`       // ACTIVE | REVOKED | EXPIRED
	RevokeReason string `json:"revokeReason"`
	Metadata     string `json:"metadata"`
	TxID         string `json:"txID"`
	Timestamp    string `json:"timestamp"`
}

// HistoryEntry represents a single ledger history record.
type HistoryEntry struct {
	TxID      string       `json:"txID"`
	Value     *Certificate `json:"value"`
	Timestamp string       `json:"timestamp"`
	IsDelete  bool         `json:"isDelete"`
}

type CertContract struct {
	contractapi.Contract
}

const docType = "certificate"
const compositeKeyPrefix = "CERT"

func (cc *CertContract) IssueCertificate(ctx contractapi.TransactionContextInterface,
	certID, studentID, studentName, courseID, courseName,
	orgID, orgName, issueDate, expiryDate, metadata string) error {

	if certID == "" || studentID == "" || orgID == "" || courseID == "" {
		return fmt.Errorf("certID, studentID, orgID, and courseID are required")
	}

	compositeKey, err := ctx.GetStub().CreateCompositeKey(compositeKeyPrefix, []string{orgID, certID})
	if err != nil {
		return fmt.Errorf("failed to create composite key: %w", err)
	}

	existing, err := ctx.GetStub().GetState(compositeKey)
	if err != nil {
		return fmt.Errorf("failed to read ledger: %w", err)
	}
	if existing != nil {
		return fmt.Errorf("certificate %s already exists for org %s", certID, orgID)
	}

	cert := Certificate{
		DocType:     docType,
		CertID:      certID,
		StudentID:   studentID,
		StudentName: studentName,
		CourseID:    courseID,
		CourseName:  courseName,
		OrgID:       orgID,
		OrgName:     orgName,
		IssueDate:   issueDate,
		ExpiryDate:  expiryDate,
		Status:      "ACTIVE",
		Metadata:    metadata,
		TxID:        ctx.GetStub().GetTxID(),
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal certificate: %w", err)
	}

	if err := ctx.GetStub().PutState(compositeKey, certJSON); err != nil {
		return fmt.Errorf("failed to put state: %w", err)
	}

	// Also store by plain certID for direct lookups
	return ctx.GetStub().PutState(certID, certJSON)
}

func (cc *CertContract) GetCertificate(ctx contractapi.TransactionContextInterface, certID string) (*Certificate, error) {
	if certID == "" {
		return nil, fmt.Errorf("certID is required")
	}

	certJSON, err := ctx.GetStub().GetState(certID)
	if err != nil {
		return nil, fmt.Errorf("failed to read ledger: %w", err)
	}
	if certJSON == nil {
		return nil, fmt.Errorf("certificate %s not found", certID)
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return nil, fmt.Errorf("failed to unmarshal certificate: %w", err)
	}
	return &cert, nil
}

func (cc *CertContract) VerifyCertificate(ctx contractapi.TransactionContextInterface, certID string) (*Certificate, error) {
	cert, err := cc.GetCertificate(ctx, certID)
	if err != nil {
		return nil, err
	}

	if cert.ExpiryDate != "" && cert.Status == "ACTIVE" {
		expiry, parseErr := time.Parse("2006-01-02", cert.ExpiryDate)
		if parseErr == nil && time.Now().UTC().After(expiry) {
			cert.Status = "EXPIRED"
		}
	}

	return cert, nil
}

func (cc *CertContract) RevokeCertificate(ctx contractapi.TransactionContextInterface, certID, reason string) error {
	if certID == "" {
		return fmt.Errorf("certID is required")
	}

	cert, err := cc.GetCertificate(ctx, certID)
	if err != nil {
		return err
	}

	if cert.Status == "REVOKED" {
		return fmt.Errorf("certificate %s is already revoked", certID)
	}

	cert.Status = "REVOKED"
	cert.RevokeReason = reason
	cert.Timestamp = time.Now().UTC().Format(time.RFC3339)

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal certificate: %w", err)
	}

	compositeKey, err := ctx.GetStub().CreateCompositeKey(compositeKeyPrefix, []string{cert.OrgID, certID})
	if err != nil {
		return fmt.Errorf("failed to create composite key: %w", err)
	}
	if err := ctx.GetStub().PutState(compositeKey, certJSON); err != nil {
		return fmt.Errorf("failed to put composite key state: %w", err)
	}

	return ctx.GetStub().PutState(certID, certJSON)
}

func (cc *CertContract) GetCertificatesByStudent(ctx contractapi.TransactionContextInterface, studentID string) ([]*Certificate, error) {
	if studentID == "" {
		return nil, fmt.Errorf("studentID is required")
	}

	queryString := fmt.Sprintf(`{"selector":{"docType":"%s","studentID":"%s"}}`, docType, studentID)
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, fmt.Errorf("failed to execute rich query: %w", err)
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		result, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate results: %w", err)
		}
		var cert Certificate
		if err := json.Unmarshal(result.Value, &cert); err != nil {
			return nil, fmt.Errorf("failed to unmarshal certificate: %w", err)
		}
		certs = append(certs, &cert)
	}
	return certs, nil
}

func (cc *CertContract) GetCertificatesByOrg(ctx contractapi.TransactionContextInterface, orgID string) ([]*Certificate, error) {
	if orgID == "" {
		return nil, fmt.Errorf("orgID is required")
	}

	resultsIterator, err := ctx.GetStub().GetStateByPartialCompositeKey(compositeKeyPrefix, []string{orgID})
	if err != nil {
		return nil, fmt.Errorf("failed to get certificates by org: %w", err)
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		result, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate results: %w", err)
		}
		var cert Certificate
		if err := json.Unmarshal(result.Value, &cert); err != nil {
			return nil, fmt.Errorf("failed to unmarshal certificate: %w", err)
		}
		certs = append(certs, &cert)
	}
	return certs, nil
}

func (cc *CertContract) GetCertificateHistory(ctx contractapi.TransactionContextInterface, certID string) (string, error) {
	if certID == "" {
		return "", fmt.Errorf("certID is required")
	}

	historyIterator, err := ctx.GetStub().GetHistoryForKey(certID)
	if err != nil {
		return "", fmt.Errorf("failed to get history: %w", err)
	}
	defer historyIterator.Close()

	var history []HistoryEntry
	for historyIterator.HasNext() {
		modification, err := historyIterator.Next()
		if err != nil {
			return "", fmt.Errorf("failed to iterate history: %w", err)
		}

		entry := HistoryEntry{
			TxID:      modification.TxId,
			Timestamp: time.Unix(modification.Timestamp.Seconds, int64(modification.Timestamp.Nanos)).UTC().Format(time.RFC3339),
			IsDelete:  modification.IsDelete,
		}

		if !modification.IsDelete && modification.Value != nil {
			var cert Certificate
			if err := json.Unmarshal(modification.Value, &cert); err == nil {
				entry.Value = &cert
			}
		}
		history = append(history, entry)
	}

	historyJSON, err := json.Marshal(history)
	if err != nil {
		return "", fmt.Errorf("failed to marshal history: %w", err)
	}
	return string(historyJSON), nil
}

func (cc *CertContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	now := time.Now().UTC()
	issueDate := now.Format("2006-01-02")
	expiryDate := now.AddDate(2, 0, 0).Format("2006-01-02")

	sampleCerts := []Certificate{
		{CertID: "TP-FSWD-001", StudentID: "student01", StudentName: "Alice Chen", CourseID: "FSWD-101", CourseName: "Full-Stack Web Dev", OrgID: "techpulse", OrgName: "TechPulse Academy", IssueDate: issueDate, ExpiryDate: expiryDate},
		{CertID: "TP-CNM-002", StudentID: "student02", StudentName: "Bob Martinez", CourseID: "CNM-201", CourseName: "Cloud-Native Microservices", OrgID: "techpulse", OrgName: "TechPulse Academy", IssueDate: issueDate, ExpiryDate: expiryDate},
		{CertID: "DF-PGA-001", StudentID: "student03", StudentName: "Carol Wang", CourseID: "PGA-101", CourseName: "PostgreSQL Administration", OrgID: "dataforge", OrgName: "DataForge Institute", IssueDate: issueDate, ExpiryDate: expiryDate},
		{CertID: "DF-DPE-002", StudentID: "student04", StudentName: "David Kim", CourseID: "DPE-201", CourseName: "Data Pipeline Engineering", OrgID: "dataforge", OrgName: "DataForge Institute", IssueDate: issueDate, ExpiryDate: expiryDate},
		{CertID: "NP-AML-001", StudentID: "student05", StudentName: "Eva Patel", CourseID: "AML-101", CourseName: "Applied Machine Learning", OrgID: "neuralpath", OrgName: "NeuralPath Labs", IssueDate: issueDate, ExpiryDate: expiryDate},
		{CertID: "NP-LFT-002", StudentID: "student06", StudentName: "Frank Liu", CourseID: "LFT-201", CourseName: "LLM Fine-Tuning Workshop", OrgID: "neuralpath", OrgName: "NeuralPath Labs", IssueDate: issueDate, ExpiryDate: expiryDate},
	}

	for _, cert := range sampleCerts {
		err := cc.IssueCertificate(ctx,
			cert.CertID, cert.StudentID, cert.StudentName,
			cert.CourseID, cert.CourseName,
			cert.OrgID, cert.OrgName,
			cert.IssueDate, cert.ExpiryDate, "")
		if err != nil {
			return fmt.Errorf("failed to issue sample cert %s: %w", cert.CertID, err)
		}
	}

	return nil
}
