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

// templateKey: template key (uuid) associated with templateRef in certificate info
// templateSource: source code of template
// sourceType: format type of source (example: json)
// version: version of template
// issuerId: issuer id or reference on blockchain
// issuerName: name of academic institution

// TemplateRecord store template source code of issued certificate
type CertificateTemplate struct {
	TemplateSource interface{} `json:"template_source"`
	SourceType     string      `json:"source_type"`
	Version        string      `json:"version"`
	IssuerId       string      `json:"issuer_id"`
	IssuerName     string      `json:"issuer_name"`
}

// QueryResult structure used for handling result of query
type QueryResult struct {
	Key    string               `json:"key"`
	Record *CertificateTemplate `json:"record"`
}

// HistoryQueryResult used for handling result modification history of certificate
type HistoryQueryResult struct {
	Value     *CertificateTemplate `json:"value"`
	TxId      string               `json:"txid"`
	Timestamp time.Time            `json:"timestamp"`
	IsDelete  bool                 `json:"is_delete"`
}

func (s *SmartContract) PutTemplate(
	ctx contractapi.TransactionContextInterface,
	templateKey string,
	templateSource interface{},
	sourceType, version, issuerId, issuerName string) error {

	cert, _ := s.QueryTemplate(ctx, templateKey)
	if cert != nil {
		return fmt.Errorf("Template %s already issued", templateKey)
	}

	template := CertificateTemplate{
		TemplateSource: templateSource,
		SourceType:     sourceType,
		Version:        version,
		IssuerId:       issuerId,
		IssuerName:     issuerName,
	}

	dataBytes, err := json.Marshal(template)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(templateKey, dataBytes)
}

func (s *SmartContract) QueryTemplate(ctx contractapi.TransactionContextInterface, certKey string) (*CertificateTemplate, error) {
	dataBytes, err := ctx.GetStub().GetState(certKey)
	if err != nil {
		return nil, fmt.Errorf("Failed to read from world state. %s", err.Error())
	}

	if dataBytes == nil {
		return nil, fmt.Errorf("%s does not exist", certKey)
	}

	template := new(CertificateTemplate)
	err = json.Unmarshal(dataBytes, template)
	if err != nil {
		return nil, err
	}

	return template, nil
}

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

		record := new(CertificateTemplate)
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
		log.Panicf("Error create CertificateTemplate chaincode: %s", err.Error())
	}

	server := &shim.ChaincodeServer{
		CCID:     config.CCID,
		Address:  config.Address,
		CC:       chaincode,
		TLSProps: getTLSProperties(),
	}

	if err := server.Start(); err != nil {
		log.Panicf("Error starting CertificateTemplate chaincode: %s", err.Error())
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
