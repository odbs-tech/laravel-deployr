#!/bin/bash
# Step 8: Database installation (MySQL or PostgreSQL)

step_database() {
    print_header "Step 8 — Installing $DB_TYPE"

    if [ "$DB_TYPE" = "mysql" ]; then
        _install_mysql
    else
        _install_postgresql
    fi

    complete_step 8
}

_install_mysql() {
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql

    local db_host_spec="localhost"
    [ "$DB_REMOTE_ACCESS" = "true" ] && db_host_spec="%"

    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'${db_host_spec}' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';"
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${db_host_spec}';"
    mysql -e "FLUSH PRIVILEGES;"

    if [ "$DB_REMOTE_ACCESS" = "true" ]; then
        # Search across all common mysqld config locations
        local mysql_cnf
        mysql_cnf=$(find /etc/mysql -name "mysqld.cnf" -o -name "my.cnf" 2>/dev/null | head -1)

        if [ -n "$mysql_cnf" ]; then
            if grep -q "^bind-address" "$mysql_cnf"; then
                sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' "$mysql_cnf"
            else
                printf '\n[mysqld]\nbind-address = 0.0.0.0\n' >> "$mysql_cnf"
            fi
            systemctl restart mysql
        else
            print_warning "Could not find mysqld config file. Set bind-address manually."
        fi

        ufw allow 3306/tcp
        print_success "MySQL remote access enabled (port 3306)."
    fi

    print_success "MySQL installed. User '$DB_USER' and database '$DB_NAME' created."
}

_install_postgresql() {
    apt-get install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql

    sudo -u postgres psql -c "DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${DB_USER}') THEN
                CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';
            END IF;
        END
    \$\$;"

    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null \
        || print_warning "Database '${DB_NAME}' already exists."

    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

    local pg_hba pg_conf
    pg_hba=$(find /etc/postgresql -name pg_hba.conf | head -1)
    pg_conf=$(find /etc/postgresql -name postgresql.conf | head -1)

    if [ -n "$pg_hba" ]; then
        if [ "$DB_REMOTE_ACCESS" = "true" ]; then
            # Use 'all' for the database column — more compatible with pg_hba.conf spec
            if ! grep -qP "^host\s+all\s+${DB_USER}\s+0\.0\.0\.0/0" "$pg_hba"; then
                echo "host    all    ${DB_USER}    0.0.0.0/0    md5" >> "$pg_hba"
            fi
            if [ -n "$pg_conf" ]; then
                sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '*'/" "$pg_conf"
            fi
            ufw allow 5432/tcp
            print_success "PostgreSQL remote access enabled (port 5432)."
        else
            if ! grep -qP "^host\s+${DB_NAME}\s+${DB_USER}\s+127\.0\.0\.1/32" "$pg_hba"; then
                echo "host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    md5" >> "$pg_hba"
            fi
        fi
        systemctl restart postgresql
    fi

    print_success "PostgreSQL installed. User '$DB_USER' and database '$DB_NAME' created."
}
