ansible-role-interworx
=========

Ansible role that installs interworx and activates the provided license key.

Requirements
------------

el6, el7

Role Variables
--------------

Available variables are listed below, along with default values (see `defaults/main.yml`):

    iw_release_channel: "release"

The Interworx release channel to perform the installation from.  Options are `stable`, `release`, `release-candidate`, and `beta`.

    iw_activate_license: true

Disable this if you do not want to activate an Interworx license.

    iw_license_key: ""

Interworx license key to install on the server. Required unless `iw_activate_license` is false.

    iw_master_email: ""

Interworx master nodeworx user email address. Required unless `iw_activate_license` is false.

    iw_master_password: ""
	
Interworx master nodeworx user password. Required unless `iw_activate_license` is false.	

    iw_ns1: ""
    iw_ns2: ""
    iw_ns3: ""

Default nameservers to configure with newly created Siteworx accounts (i.e. ns1.nexcess.net, etc).

    iw_accept_eula: true

Automatically accept the Interworx EULA. Without this the first login will require acceptance.

    iw_install_script_url: "https://updates.interworx.com/iworx/scripts/iworx-cp-install.sh"
	
Interworx install script location.	

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: server
      roles:
         - { role: nexcess.interworx }

License
-------

MIT

Author Information
------------------

Paul Oehler <poehler@interworx.com>
