FROM node:18-bullseye

ARG JF_TOKEN

# Create app directory
WORKDIR /usr/src/app
COPY package*.json ./
# Copy dependencies installed by CI
COPY node_modules node_modules

EXPOSE 3000

COPY server.js ./
COPY public public/
COPY views views/
COPY fake-creds.txt /usr/src/
CMD [ "node", "server.js" ]