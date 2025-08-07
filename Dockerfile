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
    CATALINA_HOME=/usr/share/tomcat9 \
    CATALINA_BASE=/var/lib/tomcat9

# Create directories and copy files
WORKDIR /root
COPY setup.sql start.sh /root/
COPY guacamole.properties /etc/guacamole/
RUN mkdir -p /etc/guacamole/lib /var/run/mysqld /usr/share/tomcat9/logs /etc/guacamole/extensions && \
    chmod +x /root/start.sh && \
    chown -R mysql:root /var/run/mysqld

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        curl \
        ca-certificates \
        guacd \
        tomcat9 \
        iproute2 \
        mariadb-server \
        libmariadb-java && \
    # Get latest Cloudflared version
    CLOUDFLARED_VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep 'tag_name' | cut -d\" -f4) && \
    wget -q https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64.deb -O cloudflared.deb && \
    dpkg -i cloudflared.deb && \
    # Get latest Guacamole version
    GUACAMOLE_VERSION=$(curl -s https://downloads.apache.org/guacamole/ | grep -oP '<a href="\d+\.\d+\.\d+/'  | grep -oP '\d+\.\d+\.\d+' | sort -V | tail -n 1) && \
    wget -q https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-${GUACAMOLE_VERSION}.war -O /var/lib/tomcat9/webapps/guacamole.war && \
    wget -q https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-auth-jdbc-${GUACAMOLE_VERSION}.tar.gz -O guacamole-auth-jdbc.tar.gz && \
    tar xvfz guacamole-auth-jdbc.tar.gz && \
    cp guacamole-auth-jdbc-${GUACAMOLE_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACAMOLE_VERSION}.jar /etc/guacamole/extensions && \
    # Setup Guacamole links
    ln -s /etc/guacamole/ /var/lib/tomcat9/.guacamole && \
    ln -s /usr/share/java/mariadb-java-client.jar /etc/guacamole/lib/ && \
    # Cleanup
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* cloudflared.deb guacamole-auth-jdbc.tar.gz guacamole-auth-jdbc-${GUACAMOLE_VERSION}

# Copy Cloudflared config and setup tunnel
COPY config.yml /root/.cloudflared/
RUN cloudflared tunnel login && \
    cloudflared tunnel create guacamole && \
    cloudflared tunnel route dns guacamole guacamole

EXPOSE 8080/tcp

CMD ["/root/start.sh"]