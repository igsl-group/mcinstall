## One liner installation script

Prepare a one liner script for following app installation.

### Background

an self developed ITSM web application.
which contain following components:

1. Java Spring book backend
2. Nginx Vue.js frontend
3. postgreDB
4. kafka
5. Redis

### Information parameter
App name: MCdesk
Our App repository example path:
https://repo.magiccreative.ai/repository/magic-creative-docker-group/v2/mcdesk-backend/manifests/20260624-51-qa-v2-0-1-29-5-70916dc48e
https://repo.magiccreative.ai/repository/magic-creative-docker-group/v2/mcdesk-frontend/manifests/20260624-51-qa-v2-0-1-29-5-70916dc48e

### Requirement
- the script should be able to run on linux.
- the app should be installed on docker with single docker-compose file.
- expose the 80 port to access frontend
- include an cloudflare tunnel to support public aceess.
- the script should prompt user for neccessary information like tunnel id, port no etc with default value.

### Reference:

mcdesk backend:

/home/pine/git/igs/deployment/mtrc-onperm-environment/deployments/mtrc-dev/hqsitsma203v/docker-compose.yml

mcdesk backend environment:
/home/pine/git/igs/deployment/mtrc-onperm-environment/deployments/mtrc-dev/hqsitsma203v/mcdesk.env

frontend:
/home/pine/git/igs/deployment/mtrc-onperm-environment/deployments/mtrc-dev/hqsitsma201v/frontend-server-config/docker-compose.yml

#### frontend env
MCDESK_TAG=20260624-51-qa-v2-0-1-29-5-70916dc48e

other component:

- redis
- postgreDB
- kafka

study the example docker-compose and .env files and try to combine into one docker-compose.yml
