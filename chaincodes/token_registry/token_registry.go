/*
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
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

// TokenId: token_id (uuid)
// CertificateId: certificate_id (uuid) associated with tokens
// Owner: owner email address
// Transferable: boolean flag to identify transferable capability
// Amount: amount of tokens hold in this address
// MonthlyTokenQuota: monthly token quota allowed. If zero means, no refill given after quota spent out.
// AccessQuota: access quota per one-token.
// AvailableAccesses: total remaining access quota of all tokens hold
// ExpiryDate: expiration date of tokens (if any specified) (nullable)
// LastUsedAt: last time operation performed on this tokens address
// Issuer: issuer email address
// IssuerRef: token_id references used to issued this tokens (nullable)
// IsRevoked: boolean flag if token has been revoked

// AccessTokenRegistry describes access tokens usage within platform
type AccessTokenRegistry struct {
	TokenId           string `json:"token_id"`
	CertificateId     string `json:"certificate_id"`
	Owner             string `json:"owner"`
	Transferable      bool   `json:"transferable"`
	Amount            int64  `json:"amount"`
	MonthlyTokenQuota int64  `json:"monthly_token_quota"`
	AccessQuota       int64  `json:"access_quota"`
	AvailableAccesses int64  `json:"available_accesses"`
	ExpiryDate        int64  `json:"expiry_date"`
	LastUsedAt        int64  `json:"last_used_at"`
	Issuer            string `json:"issuer"`
	IssuerRef         string `json:"issuer_ref"`
	IsRevoked         bool   `json:"is_revoked"`
}

// QueryResult structure used for handling result of query
type QueryResult struct {
	Key    string               `json:"key"`
	Record *AccessTokenRegistry `json:"record"`
}

// HistoryQueryResult used for handling result modification history of certificate
type HistoryQueryResult struct {
	Value     *AccessTokenRegistry `json:"value"`
	TxId      string               `json:"txid"`
	Timestamp time.Time            `json:"timestamp"`
	IsDelete  bool                 `json:"is_delete"`
}

const (
	IssuerRoot = "ROOT"
)

// IssueRootToken grant root access token to Academic and Certificate Holder
func (s *SmartContract) IssueRootToken(ctx contractapi.TransactionContextInterface, tokenId, certificateId, owner string) error {
	_, err := s.QueryToken(ctx, tokenId)
	if err == nil {
		return fmt.Errorf("TokenId %s already exists", tokenId)
	}

	token := AccessTokenRegistry{
		TokenId:           tokenId,
		CertificateId:     certificateId,
		Owner:             owner,
		Transferable:      false,
		Amount:            1,
		MonthlyTokenQuota: 0,
		AccessQuota:       0,
		AvailableAccesses: 0,
		ExpiryDate:        0,
		LastUsedAt:        0,
		Issuer:            IssuerRoot,
		IssuerRef:         "",
		IsRevoked:         false,
	}

	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(tokenId, tokenBytes)
}

// IssueTransferableToken grant transferable access token. Require root token (issuer) reference.
func (s *SmartContract) IssueTransferableToken(ctx contractapi.TransactionContextInterface, tokenId, issuerTokenId, recipient string,
	amount, monthlyTokenQuota, expiryDate int64) error {

	if amount <= 0 || monthlyTokenQuota < 0 {
		return fmt.Errorf("Amount and Monthly Token Quota must be positive integer")
	}

	if expiryDate > 0 && expiryDate < time.Now().Unix() {
		return fmt.Errorf("Expiry date must be greater than current time")
	}

	_, err := s.QueryToken(ctx, tokenId)
	if err == nil {
		return fmt.Errorf("TokenId %s already exists", tokenId)
	}

	issuerToken, err := s.QueryToken(ctx, issuerTokenId)
	if err != nil {
		return fmt.Errorf("Error query issuer token: %s", err.Error())
	}

	// Issuer must be root to grant transferable access token
	if !isRootToken(issuerToken) {
		return fmt.Errorf("Issuer does not have permission to grant transferable tokens")
	}

	if issuerToken.IsRevoked {
		return fmt.Errorf("Issuer token has been revoked")
	}

	token := AccessTokenRegistry{
		TokenId:           tokenId,
		CertificateId:     issuerToken.CertificateId,
		Owner:             recipient,
		Transferable:      true,
		Amount:            amount,
		MonthlyTokenQuota: monthlyTokenQuota,
		AccessQuota:       1,
		AvailableAccesses: amount,
		ExpiryDate:        expiryDate,
		LastUsedAt:        0,
		Issuer:            issuerToken.Owner,
		IssuerRef:         issuerTokenId,
		IsRevoked:         false,
	}

	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(tokenId, tokenBytes)
}

// IssueStandardToken transfer access token to the external users such employer and non-registered user in platform
func (s *SmartContract) IssueStandardToken(ctx contractapi.TransactionContextInterface, tokenId, issuerTokenId, recipient string,
	amount, accessQuota, expiryDate int64) error {

	if amount <= 0 || accessQuota <= 0 {
		return fmt.Errorf("Amount and Access Quota must be greater than zero")
	}

	if expiryDate > 0 && expiryDate < time.Now().Unix() {
		return fmt.Errorf("Expiry date must be greater than current time")
	}

	_, err := s.QueryToken(ctx, tokenId)
	if err == nil {
		return fmt.Errorf("TokenId %s already exists", tokenId)
	}

	issuerToken, err := s.QueryToken(ctx, issuerTokenId)
	if err != nil {
		return err
	}

	// Assert issuer token valid
	tokenStatus := checkTokenStatus(issuerToken)
	if tokenStatus != "VALID" {
		return fmt.Errorf("Issuer token is not valid. Status: %s", tokenStatus)
	}

	isIssuerRoot := isRootToken(issuerToken)
	issuerAmountBefore := issuerToken.Amount
	issuerAccessesBefore := issuerToken.AvailableAccesses

	// If issuer is not root, check the requirements
	// Else if root then nothing to deduct

	if !isIssuerRoot {
		// Assert issuer token is transferable
		if !issuerToken.Transferable {
			return fmt.Errorf("Issuer does not have permission to issuing transferable tokens")
		}

		// Assert issuer have enough balance
		if issuerToken.AvailableAccesses < (amount * accessQuota) {
			return fmt.Errorf("Issuer does not have enough amount to transfer")
		}

		// Handle monthly token quota
		replenishAccessToken(issuerToken)
		issuerAmountBefore = issuerToken.Amount
		issuerAccessesBefore = issuerToken.AvailableAccesses

		// Deduct issuer token amount
		issuerToken.AvailableAccesses -= (amount * accessQuota)
		issuerToken.Amount = int64(math.Ceil(float64(issuerToken.AvailableAccesses) / float64(issuerToken.AccessQuota)))
		issuerToken.LastUsedAt = time.Now().Unix()

		issuerTokenBytes, err := json.Marshal(issuerToken)
		if err != nil {
			return err
		}

		err = ctx.GetStub().PutState(issuerTokenId, issuerTokenBytes)
		if err != nil {
			return err
		}
	}

	// Transfer standard access tokens
	token := AccessTokenRegistry{
		TokenId:           tokenId,
		CertificateId:     issuerToken.CertificateId,
		Owner:             recipient,
		Transferable:      false,
		Amount:            amount,
		MonthlyTokenQuota: 0,
		AccessQuota:       accessQuota,
		AvailableAccesses: amount * accessQuota,
		ExpiryDate:        expiryDate,
		LastUsedAt:        0,
		Issuer:            issuerToken.Owner,
		IssuerRef:         issuerTokenId,
		IsRevoked:         false,
	}

	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	err = ctx.GetStub().PutState(tokenId, tokenBytes)
	if err != nil {
		// If issuer is root, then return error and nothing to rollback
		if isIssuerRoot {
			return err
		}

		// Rollback (refund) issuer token amount
		issuerToken.Amount = issuerAmountBefore
		issuerToken.AvailableAccesses = issuerAccessesBefore
		issuerToken.LastUsedAt = time.Now().Unix()

		issuerTokenBytes, err1 := json.Marshal(issuerToken)
		if err1 != nil {
			return fmt.Errorf("Failed to refund issuer: %s, Err: %s, Previous Amount: %d, Available Accesses: %d",
				err1.Error(), err.Error(), issuerAmountBefore, issuerAccessesBefore)
		}

		err1 = ctx.GetStub().PutState(issuerTokenId, issuerTokenBytes)
		if err1 != nil {
			return fmt.Errorf("Failed to refund issuer: %s, Err: %s, Previous Amount: %d, Available Accesses: %d",
				err1.Error(), err.Error(), issuerAmountBefore, issuerAccessesBefore)
		}
	}

	return nil
}

// ChangeTokenOwner change token owner (recipient) for reset or resend email notification
func (s *SmartContract) ChangeTokenOwner(ctx contractapi.TransactionContextInterface, tokenId, owner string) error {
	token, err := s.QueryToken(ctx, tokenId)
	if err != nil {
		return err
	}

	// Assert token status valid
	tokenStatus := checkTokenStatus(token)
	if tokenStatus != "VALID" {
		return fmt.Errorf("Error in change token owner. TokenId: %s, Status: %s", tokenId, tokenStatus)
	}

	// Assert not root token
	if isRootToken(token) {
		return fmt.Errorf("Error in change token owner. TokenId: %s is root token", tokenId)
	}

	// If there is no change, do nothing
	if strings.ToLower(token.Owner) == strings.ToLower(owner) {
		return nil
	}

	// Change token owner
	token.Owner = owner

	// Write token changes
	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(tokenId, tokenBytes)
}

// ConsumeToken deduct available access by 1 from tokenId
func (s *SmartContract) ConsumeToken(ctx contractapi.TransactionContextInterface, tokenId string) error {
	token, err := s.QueryToken(ctx, tokenId)
	if err != nil {
		return err
	}

	// Assert token status valid
	tokenStatus := checkTokenStatus(token)
	if tokenStatus != "VALID" {
		return fmt.Errorf("Error in consuming token. TokenId: %s, Status: %s", tokenId, tokenStatus)
	}

	// If not root token, consume token
	if !isRootToken(token) {
		// Handle monthly token quota
		replenishAccessToken(token)

		// Consume Available Accesses
		token.AvailableAccesses -= 1

		// Adjust amount, if consumed access finish one token access quota
		if math.Mod(float64(token.AvailableAccesses), float64(token.AccessQuota)) == 0.0 {
			token.Amount -= 1
		}
	}

	// Update last used timestamp
	token.LastUsedAt = time.Now().Unix()

	// Write token changes
	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(tokenId, tokenBytes)
}

// RevokeToken revoke all tokens hold in tokenId
func (s *SmartContract) RevokeToken(ctx contractapi.TransactionContextInterface, tokenId string) error {
	token, err := s.QueryToken(ctx, tokenId)
	if err != nil {
		return err
	}

	tokenStatus := checkTokenStatus(token)
	if tokenStatus != "VALID" {
		return fmt.Errorf("Token Id %s cannot be revoke, Current status: %s", tokenId, tokenStatus)
	}

	if token.IsRevoked {
		return fmt.Errorf("TokenId %s already revoked", tokenId)
	}

	token.IsRevoked = true
	tokenBytes, err := json.Marshal(token)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(tokenId, tokenBytes)
}

// QueryToken returns the token stored in the state with given id
func (s *SmartContract) QueryToken(ctx contractapi.TransactionContextInterface, tokenId string) (*AccessTokenRegistry, error) {
	dataBytes, err := ctx.GetStub().GetState(tokenId)
	if err != nil {
		return nil, fmt.Errorf("Error in query token: %s, tokenId: %s", err.Error(), tokenId)
	}

	if dataBytes == nil {
		return nil, fmt.Errorf("TokenId %s does not exist", tokenId)
	}

	token := new(AccessTokenRegistry)
	err = json.Unmarshal(dataBytes, token)
	if err != nil {
		return nil, err
	}

	return token, nil
}

// QueryTokenStatus get token status of tokenId
func (s *SmartContract) QueryTokenStatus(ctx contractapi.TransactionContextInterface, tokenId string) (string, error) {
	token, err := s.QueryToken(ctx, tokenId)
	if err != nil {
		return "", err
	}
	return checkTokenStatus(token), nil
}

// QueryRecords uses a query string to perform a query for certificates.
// Query string matching state database syntax is passed in and executed as is.
func (s *SmartContract) QueryRecords(ctx contractapi.TransactionContextInterface, queryString string) ([]*AccessTokenRegistry, error) {
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	return constructQueryResponseFromIterator(resultsIterator)
}

func constructQueryResponseFromIterator(resultsIterator shim.StateQueryIteratorInterface) ([]*AccessTokenRegistry, error) {
	records := []*AccessTokenRegistry{}

	for resultsIterator.HasNext() {
		queryResult, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		record := AccessTokenRegistry{}
		err = json.Unmarshal(queryResult.Value, &record)
		if err != nil {
			return nil, err
		}
		records = append(records, &record)
	}

	return records, nil
}

// GetHistoryForKey get modification history of access token
func (s *SmartContract) GetHistoryForKey(ctx contractapi.TransactionContextInterface, key string) ([]HistoryQueryResult, error) {
	resultsIterator, err := ctx.GetStub().GetHistoryForKey(key)
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

		record := new(AccessTokenRegistry)
		err = json.Unmarshal(queryResponse.Value, record)
		if err != nil {
			return nil, err
		}

		timestamp := time.Unix(int64(queryResponse.Timestamp.Seconds), int64(queryResponse.Timestamp.Nanos)).Local()

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

func isRootToken(token *AccessTokenRegistry) bool {
	return token.IssuerRef == "" && token.Issuer == IssuerRoot
}

// checkTokenStatus returns status of token.
// - Revoked: token already revoked and cannot be used for further operation.
// - Spent: token already spent out. No further quota available to consume. Token with Monthly Token Quota will replenish and status can be valid in the next month.
// - Expired: token has been expired. There may be some remaining accesses hold.
// - Valid: token still valid and can be consume.
func checkTokenStatus(token *AccessTokenRegistry) string {
	if token == nil {
		return "INVALID"
	}

	if token.IsRevoked {
		return "REVOKED"
	}

	// For non-root token check requirements
	if !isRootToken(token) {
		if token.AvailableAccesses == 0 && token.MonthlyTokenQuota == 0 {
			return "SPENT"
		}
		if token.ExpiryDate != 0 {
			tExpiryDate := time.Unix(token.ExpiryDate, 0)
			if tExpiryDate.Before(time.Now()) {
				return "EXPIRED"
			}
		}
	}

	return "VALID"
}

// replenishAccessToken refill access token if issuer had monthly quota
func replenishAccessToken(t *AccessTokenRegistry) {
	if t == nil || t.MonthlyTokenQuota == 0 {
		return
	}

	if t.LastUsedAt != 0 {
		tlastUsedAt := time.Unix(t.LastUsedAt, 0)
		if tlastUsedAt.Month() != time.Now().Month() {
			t.Amount = t.MonthlyTokenQuota
			t.AvailableAccesses = t.Amount * t.AccessQuota
			t.LastUsedAt = time.Now().Unix()
		}
	}
}

func main() {
	config := serverConfig{
		CCID:    os.Getenv("CHAINCODE_ID"),
		Address: os.Getenv("CHAINCODE_SERVER_ADDRESS"),
	}

	chaincode, err := contractapi.NewChaincode(new(SmartContract))

	if err != nil {
		log.Panicf("Error create AccessTokenRegistry chaincode: %s", err.Error())
	}

	server := &shim.ChaincodeServer{
		CCID:     config.CCID,
		Address:  config.Address,
		CC:       chaincode,
		TLSProps: getTLSProperties(),
	}

	if err := server.Start(); err != nil {
		log.Panicf("Error starting AccessTokenRegistry chaincode: %s", err.Error())
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
