/*
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type serverConfig struct {
	CCID    string
	Address string
}

type SmartContract struct {
	contractapi.Contract
}

// certKey: certificate_id (uuid) use to issue certificate
// certSignature: digital signature of certificate signed by issuer (academic institution)
// templateRef: template key reference (uuid) use to generate certificate
// courseName: primary course name
// moduleName: secondary course name (module name or course name (ii))
// certificateHolder: name of certificate holder
// email: email of certificate holder
// isRevoked: revocation status of certificate
// issuerId: identity of reference issuer on blockchain
// issuerName: name of academic institution
// issuedAt: actual date certificate issued physically
// extras: additional details of the certificates (associated course attributes)

// CertificateRecord describes basic details of certificate record detail
type CertificateRecord struct {
	CertificateSignature string      `json:"certificate_signature"`
	TemplateRef          string      `json:"template_ref"`
	CourseName           string      `json:"course_name"`
	ModuleName           string      `json:"module_name"`
	CertificateHolder    string      `json:"certificate_holder"`
	Email                string      `json:"email"`
	IsRevoked            bool        `json:"is_revoked"`
	IssuerId             string      `json:"issuer_id"`
	IssuerName           string      `json:"issuer_name"`
	IssuedAt             string      `json:"issued_at"`
	Extras               interface{} `json:"extras"`
}

// QueryResult structure used for handling result of query
type QueryResult struct {
	Key    string             `json:"key"`
	Record *CertificateRecord `json:"record"`
}

// HistoryQueryResult used for handling result modification history of certificate
type HistoryQueryResult struct {
	Value     *CertificateRecord `json:"value"`
	TxId      string             `json:"txid"`
	Timestamp time.Time          `json:"timestamp"`
	IsDelete  bool               `json:"is_delete"`
}

// IssueCertificate add new certificate into ledger
func (s *SmartContract) IssueCertificate(ctx contractapi.TransactionContextInterface,
	certKey, certSignature, templateRef, courseName, moduleName, certHolder, email, issuerId,
	issuer, issuedAt string, extras interface{}) error {

	cert, _ := s.QueryCertificate(ctx, certKey)
	if cert != nil {
		return fmt.Errorf("Certificate %s already issued", certKey)
	}

	certificate := CertificateRecord{
		CertificateSignature: certSignature,
		TemplateRef:          templateRef,
		CourseName:           courseName,
		ModuleName:           moduleName,
		CertificateHolder:    certHolder,
		Email:                email,
		IsRevoked:            false,
		IssuerId:             issuerId,
		IssuerName:           issuer,
		IssuedAt:             issuedAt,
		Extras:               extras,
	}

	certificateBytes, err := json.Marshal(certificate)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(certKey, certificateBytes)
}

// QueryCertificate returns the certificate stored in the world state with given id
func (s *SmartContract) QueryCertificate(ctx contractapi.TransactionContextInterface, certKey string) (*CertificateRecord, error) {
	certificateBytes, err := ctx.GetStub().GetState(certKey)
	if err != nil {
		return nil, fmt.Errorf("Failed to read from world state. %s", err.Error())
	}

	if certificateBytes == nil {
		return nil, fmt.Errorf("%s does not exist", certKey)
	}

	certificate := new(CertificateRecord)
	err = json.Unmarshal(certificateBytes, certificate)
	if err != nil {
		return nil, err
	}

	return certificate, nil
}

// RevokeCertificate revoke certificate that already issued by certKey
func (s *SmartContract) RevokeCertificate(ctx contractapi.TransactionContextInterface, certKey string) error {
	certificate, err := s.QueryCertificate(ctx, certKey)
	if err != nil {
		return err
	}

	if certificate.IsRevoked {
		return fmt.Errorf("Certificate %s already revoked", certKey)
	}

	certificate.IsRevoked = true
	certificateBytes, err := json.Marshal(certificate)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(certKey, certificateBytes)
}

// QueryRecords uses a query string to perform a query for certificates.
// Query string matching state database syntax is passed in and executed as is.
func (s *SmartContract) QueryRecords(ctx contractapi.TransactionContextInterface, queryString string) ([]*CertificateRecord, error) {
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	return constructQueryResponseFromIterator(resultsIterator)
}

func constructQueryResponseFromIterator(resultsIterator shim.StateQueryIteratorInterface) ([]*CertificateRecord, error) {
	records := []*CertificateRecord{}

	for resultsIterator.HasNext() {
		queryResult, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		record := CertificateRecord{}
		err = json.Unmarshal(queryResult.Value, &record)
		if err != nil {
			return nil, err
		}
		records = append(records, &record)
	}

	return records, nil
}

// GetHistoryForKey get modification history of certificate
func (s *SmartContract) GetHistoryForKey(ctx contractapi.TransactionContextInterface, certKey string) ([]HistoryQueryResult, error) {
	resultsIterator, err := ctx.GetStub().GetHistoryForKey(certKey)
	if err != nil {
		return []HistoryQueryResult{}, err
	}

	defer resultsIterator.Close()

	results := []HistoryQueryResult{}

	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		record := new(CertificateRecord)
		err = json.Unmarshal(queryResponse.Value, record)
		if err != nil {
			return nil, err
		}

		timestamp := time.Unix(int64(queryResponse.Timestamp.Seconds), int64(queryResponse.Timestamp.Nanos))

		r := HistoryQueryResult{
			Value:     record,
			TxId:      queryResponse.TxId,
			Timestamp: timestamp,
			IsDelete:  queryResponse.IsDelete,
		}

		results = append(results, r)
	}

	return results, nil
}

func main() {
	config := serverConfig{
		CCID:    os.Getenv("CHAINCODE_ID"),
		Address: os.Getenv("CHAINCODE_SERVER_ADDRESS"),
	}

	chaincode, err := contractapi.NewChaincode(new(SmartContract))

	if err != nil {
		log.Panicf("Error create CertificateInfo chaincode: %s", err.Error())
	}

	server := &shim.ChaincodeServer{
		CCID:     config.CCID,
		Address:  config.Address,
		CC:       chaincode,
		TLSProps: getTLSProperties(),
	}

	if err := server.Start(); err != nil {
		log.Panicf("Error starting CertificateInfo chaincode: %s", err.Error())
	}
}

func getTLSProperties() shim.TLSProperties {
	// Check if chaincode is TLS enabled
	tlsDisabledStr := getEnvOrDefault("CHAINCODE_TLS_DISABLED", "true")
	key := getEnvOrDefault("CHAINCODE_TLS_KEY", "")
	cert := getEnvOrDefault("CHAINCODE_TLS_CERT", "")
	clientCACert := getEnvOrDefault("CHAINCODE_CLIENT_CA_CERT", "")

	// convert tlsDisabledStr to boolean
	tlsDisabled := getBoolOrDefault(tlsDisabledStr, false)
	var keyBytes, certBytes, clientCACertBytes []byte
	var err error

	if !tlsDisabled {
		keyBytes, err = os.ReadFile(key)
		if err != nil {
			log.Panicf("error while reading the crypto file: %s", err)
		}
		certBytes, err = os.ReadFile(cert)
		if err != nil {
			log.Panicf("error while reading the crypto file: %s", err)
		}
	}
	// Did not request for the peer cert verification
	if clientCACert != "" {
		clientCACertBytes, err = os.ReadFile(clientCACert)
		if err != nil {
			log.Panicf("error while reading the crypto file: %s", err)
		}
	}

	return shim.TLSProperties{
		Disabled:      tlsDisabled,
		Key:           keyBytes,
		Cert:          certBytes,
		ClientCACerts: clientCACertBytes,
	}
}

func getEnvOrDefault(env, defaultVal string) string {
	value, ok := os.LookupEnv(env)
	if !ok {
		value = defaultVal
	}
	return value
}

// Note that the method returns default value if the string
// cannot be parsed!
func getBoolOrDefault(value string, defaultVal bool) bool {
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return defaultVal
	}
	return parsed
}
