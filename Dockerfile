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

# Set environment variables for the script (optional, or you can pass them at runtime)
ENV DevtronApiToken="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjphZG1pbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.-EHSyCfbwaRl43CGu72w2XZ_rFQjrE7CcWGL6Hk2ukE" \
    DevtronEndpoint="devtron-service.devtroncd" \
    DevtronApp="sample-go-app" \
    CiPipeline="ci-2-7zo6" \
    GitCommitHash="7ba1d9a4b21ea95ba949ada345918e6d977bb00b,7a973978c973f4182defbc7441e5b2ab677a351c,117237217306594a5f232564d9f80c298cd573ef" \
    Timeout=1000 \
    IgnoreCache=false

# Command to run the script
CMD ["./plugin.sh"]
