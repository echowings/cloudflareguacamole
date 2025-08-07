FROM debian:bookworm-slim

LABEL maintainer="matt@matthewrogers.org"

# Combine environment variables
ENV HOME=/root \
    LC_ALL=C.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    GOPATH=/root/go \
    DEBIAN_FRONTEND=noninteractive \
    CLOUDFLARETEAM=yourcloudflareteamname \
    TZ=Asia/Chongqing \
    CATALINA_HOME=/usr/share/tomcat11 \
    CATALINA_BASE=/var/lib/tomcat11

# Create directories and copy files
WORKDIR /root
COPY setup.sql start.sh /root/
COPY guacamole.properties /etc/guacamole/
RUN chmod +x /root/start.sh

# Update package sources and install dependencies
RUN echo "deb http://deb.debian.org/debian bookworm main contrib" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bookworm-security main contrib" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        curl \
        ca-certificates \
        guacd \
        tomcat11 \
        iproute2 \
        mariadb-server \
        libmariadb-java || { echo "apt-get install failed"; exit 1; }

# Create directories and set permissions
RUN mkdir -p /etc/guacamole/lib /var/run/mysqld /usr/share/tomcat11/logs /etc/guacamole/extensions && \
    chown -R mysql:root /var/run/mysqld

# Install Cloudflared
RUN CLOUDFLARED_VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep 'tag_name' | cut -d\" -f4) && \
    wget -q https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64.deb -O cloudflared.deb && \
    dpkg -i cloudflared.deb && \
    rm -f cloudflared.deb

# Install Guacamole
RUN GUACAMOLE_VERSION=$(curl -s https://downloads.apache.org/guacamole/ | grep -oP '<a href="\d+\.\d+\.\d+/' | grep -oP '\d+\.\d+\.\d+' | sort -V | tail -n 1) && \
    wget -q https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-${GUACAMOLE_VERSION}.war -O /var/lib/tomcat11/webapps/guacamole.war && \
    wget -q https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-auth-jdbc-${GUACAMOLE_VERSION}.tar.gz -O guacamole-auth-jdbc.tar.gz && \
    tar xvfz guacamole-auth-jdbc.tar.gz && \
    cp guacamole-auth-jdbc-${GUACAMOLE_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACAMOLE_VERSION}.jar /etc/guacamole/extensions && \
    rm -rf guacamole-auth-jdbc.tar.gz guacamole-auth-jdbc-${GUACAMOLE_VERSION}

# Setup Guacamole links and cleanup
RUN ln -s /etc/guacamole/ /var/lib/tomcat9/.guacamole && \
    ln -s /usr/share/java/mariadb-java-client.jar /etc/guacamole/lib/ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy Cloudflared config and setup tunnel
COPY config.yml /root/.cloudflared/
RUN cloudflared tunnel login && \
    cloudflared tunnel create guacamole && \
    cloudflared tunnel route dns guacamole guacamole

EXPOSE 8080/tcp

CMD ["/root/start.sh"]