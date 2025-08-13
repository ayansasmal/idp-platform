FROM node:18-alpine

# Install dependencies for Unleash
RUN apk add --no-cache postgresql-client curl

# Create unleash user
RUN addgroup -g 1001 unleash && \
    adduser -u 1001 -G unleash -s /bin/sh -D unleash

# Set working directory
WORKDIR /unleash

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production --silent

# Copy unleash source code
COPY . .

# Change ownership to unleash user
RUN chown -R unleash:unleash /unleash

# Switch to unleash user
USER unleash

# Expose port
EXPOSE 4242

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4242/health || exit 1

# Start unleash
CMD ["npm", "start"]