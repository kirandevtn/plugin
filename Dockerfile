# Use Alpine-based bash image
FROM alpine:3.18

# Install bash, curl, and jq
RUN apk update && \
    apk add --no-cache bash curl jq

# Set the working directory inside the container
WORKDIR /usr/src/app

# Copy your Bash script into the container
COPY plugin.sh .

# Ensure the script has execution permissions
RUN chmod +x plugin.sh

# Command to run the script
CMD ["./plugin.sh"]
