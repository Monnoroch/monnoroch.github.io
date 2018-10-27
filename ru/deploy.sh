#!/bin/sh

echo "Deploying..."

git push -f deploy HEAD:master
