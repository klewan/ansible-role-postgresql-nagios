Ansible Role: postgresql-nagios
===============================

This role is used for Nagios monitoring for a PostgreSQL instance management.

Supported OS:
-------------
* RedHat
* CentOS
* OracleLinux

Requirements
------------

None

Role Variables
--------------

Available variables are listed below, along with default values (see `defaults/main.yml`):

    # postgres password file name
    postgresql_nagios_passfile: "{{ postgresql_passfile|default('.pgpass', true) }}"

    # files to be copied to remote host
    postgresql_nagios_templates_to_copy:
      - { file: chk_postgres_wr.j2, dest: '{{ postgresql_scripts_directory }}/chk_postgres_wr', owner: '{{ postgresql_user }}', group: '{{ postgresql_group }}', mode: '0750' }

    postgresql_nagios_files_to_copy:
      - { file: check_postgres.pl, dest: '{{ postgresql_scripts_directory }}/check_postgres.pl', owner: '{{ postgresql_user }}', group: '{{ postgresql_group }}', mode: '0750' }
      - { file: check_postgres_backup_to_Networker.sh, dest: '{{ postgresql_scripts_directory }}/check_postgres_backup_to_Networker.sh', owner: '{{ postgresql_user }}', group: '{{ postgresql_group }}', mode: '0750' }

	  
Dependencies
------------

This role uses `postgresql` role.

Example Playbook
----------------

    - name: Configure Nagios monitoring for PostgreSQL instance
      hosts: pg-servers
      become: true
      become_user: '{{ postgresql_user }}'
      roles:
        - { role: postgresql-nagios, tags: postgresql_nagios }


Inside `vars/main.yml` or `group_vars/..` or `host_vars/..`:

    #---------------------------------------------
    # overrides role 'postgresql-nagios' variables
    #---------------------------------------------

    # ... etc ...


License
-------

GPLv3 - GNU General Public License v3.0

Author Information
------------------

This role was created in 2018 by [Krzysztof Lewandowski](mailto:Krzysztof.Lewandowski@fastmail.fm).


