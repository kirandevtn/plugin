# Use an official lightweight image with bash installed
FROM bash:5.1.16

# Install required dependencies (e.g., curl, jq)
RUN apk update && \
    apk add --no-cache curl jq

# Set the working directory inside the container
WORKDIR /usr/src/app

# Copy your Bash script into the container
COPY plugin.sh .

# Ensure the script has execution permissions
RUN chmod +x plugin.sh

# Command to run the script
CMD ["./plugin.sh"]
