#!/bin/sh

rm -rf -- !(_site)
mv _site/* ./
rm -rf _site
git add .
git remote add deploy https://$GITHUB_TOKEN:x-oauth-basic@github.com/$GITHUB_USER/$GITHUB_USER.github.io.git
git commit -m 'Deploy'
git push -f deploy HEAD:master
