{# This SLS serves only as a capsule to ease handling of dependencies. #}

{%- from "openvpn/map.jinja" import mapdata as map with context %}

{%- if map.manage_group is sameas false or map.user in ['nobody', 'nogroup'] %}
{%-   set manage_group = False %}
{%- else %}
{%-   set manage_group = True %}
openvpn_group:
  group.present:
    - name: {{ map.group }}
    - require_in:
      - file: openvpn_config_dir
      - sls: openvpn.config
{%- endif %}

{%- if not (map.manage_user is sameas false or map.user == 'nobody') %}
openvpn_user:
  user.present:
    - name: {{ map.user }}
    - gid: {{ map.group }}
{%-   if manage_group %}
    - require:
      - group: openvpn_group
{%-   endif %}
    - require_in:
      - file: openvpn_config_dir
      - sls: openvpn.config
{%- endif %}

openvpn_config_dir:
  file.directory:
    - name: {{ map.conf_dir }}
{%- if not grains['os_family'] == 'Windows' %}
    # Owned by root: the service user only needs to traverse it. Giving it the
    # directory let a compromised daemon rename keys/ or server/ and plant its
    # own CA.
    - mode: 750
    - user: root
    - group: {{ map.group }}
{%- endif %}
    - require_in:
      - sls: openvpn.config

{%- if grains.os_family == 'FreeBSD' %}
openvpn_kldload_if_tap:
  kmod.present:
    - name: if_tap
    - persist: True
    - require_in:
      - sls: openvpn.config
{%- endif %}
