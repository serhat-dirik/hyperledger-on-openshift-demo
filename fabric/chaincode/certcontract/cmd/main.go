package main

import (
	"log"
	"github.com/certchain/certcontract"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

func main() {
	cc, err := contractapi.NewChaincode(&certcontract.CertContract{})
	if err != nil {
		log.Fatalf("Error creating chaincode: %v", err)
	}
	if err := cc.Start(); err != nil {
		log.Fatalf("Error starting chaincode: %v", err)
	}
}
