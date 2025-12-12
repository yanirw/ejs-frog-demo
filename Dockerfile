FROM node:18-bullseye

ARG INJECTED_SECRET
# Real-world scenario simulation: Baking build-time secrets into a runtime .env file
RUN echo "AWS_ACCESS_KEY_ID=$INJECTED_SECRET" > .env

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