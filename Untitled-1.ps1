
# Change computer name to match naming convention

- name: Change Computer Name
  set_fact:
      new_computer_name: "contoso-{{ deployment_stage }}-dc01"


- name: Set computer name
  win_shell: C:\Temp\ad\library\set_computer_name.ps1 -compName {{ new_computer_name }}
  register: new_computer_name_result

- name: Collect computer name result
  debug:
    msg: "{{ new_computer_name_result }}"
  when: new_computer_name_result is changed

- name: Reboot (name changed DC01)
  win_reboot:
     connect_timeout: 15
     post_reboot_delay: 15
  when: new_computer_name_result is changed

- name: Wait for system to become reachable over WinRM
  wait_for_connection:
  timeout: 900

# Configure ADDS
- name: Install AD-Domain-Services feature
  win_feature:
    name: AD-Domain-Services
    include_management_tools: true
    include_sub_features: true
    state: present
  register: adds_result
- name: Collect ADDS provision result
  debug:
    msg: "{{adds_result}}"
- name : pause for 10 seconds before provisioning another feature
  pause:
    seconds: 10

# Configure DNS Feature
- name: Install DNS SubFeature
  win_feature:
  name: DNS
    include_sub_features: true
    include_management_tools: true
    state: present
  register: dns_result

- name: Collect dns provision result
  debug:
    msg: "{{dns_result}}"


# Reboot after ADDS configuration
- name: Reboot after ADDS configuration
  win_reboot:
    connect_timeout: 15
    post_reboot_delay: 15
  when: adds_result.reboot_required

- name: Wait for system to become reachable over WinRM
  wait_for_connection:
    timeout: 900

# Initialise Forest (Promote DC)
- name: Initialise Forest
  win_domain:
    dns_domain_name: "{{ ad_domain_name }}"
    safe_mode_password: "{{ ad_safe_mode_password }}"
  register: create_forest_result
- name: Collect computer name result
  debug:
    msg: "{{ create_forest_result }}"

- name: Reboot after forest creation
  win_reboot:
    connect_timeout: 15
    post_reboot_delay: 15
    reboot_timeout: 200
  when: create_forest_result.reboot_required

- name: Wait for system to become reachable over WinRM
  wait_for_connection:
    timeout: 900

# Ensure ADWS service is started
- name: ensure ADWS service is started
  win_service:
    name: ADWS
    state: started
  register: service_status_results

- name: Collect ADWS service status
  debug:
    msg: "{{ service_status_results }}"

# Check domain created above has completed configuration and is available
- name: Get Domain Details
  win_shell: C:\Temp\ad\library\get_domain_details.ps1 -domainName {{ ad_domain_name }}
  register: get_domain_result
  until: Test_domain_result is succeeded
  retries: 3
  delay: 120
  ignore_errors: true

- name: Collect Test Domain result
  debug:
    msg: "{{ get_domain_result }}"

# Create Site and move primary to the required Site
- name: Create Site subnets and site link
  win_shell: C:\Temp\ad\library\create_site_subnet.ps1 -pathofcsvfile C:\Temp\ad\library\create_site_subnet.csv
  register: create_site_result
  delay: 120
  vars:
    ansible_become: yes
    ansible_become_pass: "{{ dn_admin_pwd }}"
    ansible_become_flags: logon_type=new_credentials logon_flags=netcredentials_only

- name: Create Site subnets and site link results
  debug:
    msg: "{{ create_site_result }}"

# TODO: change SITE NAME into variable
- name: Move Domain Controller to the correct site
  win_shell: "$WarningPreference = 'SilentlyContinue'; Move-ADDirectoryServer -Identity {{ new_computer_name }} -Site 'AWS' | Out-Null"
  delay: 120
  vars:
    ansible_become: yes
    ansible_become_pass: "{{ dn_admin_pwd }}"
    ansible_become_flags: logon_type=new_credentials logon_flags=netcredentials_only