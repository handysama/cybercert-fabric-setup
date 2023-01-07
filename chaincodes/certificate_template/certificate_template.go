package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

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
	chaincode, err := contractapi.NewChaincode(new(SmartContract))

	if err != nil {
		fmt.Printf("Error create CertificateTemplate chaincode: %s", err.Error())
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting CertificateTemplate chaincode: %s", err.Error())
	}
}
