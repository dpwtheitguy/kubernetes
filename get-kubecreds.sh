#!/bin/bash

# Get Username and Password
kubectl get secret terminal-creds -o jsonpath='{.data.username}'| base64 --decode
kubectl get secret terminal-creds -o jsonpath='{.data.password}'| base64 --decode
