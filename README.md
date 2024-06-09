## Export Pi Hole DNS A Records to Unifi
![Screenshot](Sample.png)

### Instructions 
Pi Hole API token is available at: <piholeurl>/admin/settings.php?tab=api<br/>
Unifi Admins & Users can be modified at: <unifiurl>/admin<br/><br/>
When creating a Unifi user for API use it is recommended to choose the following options:<br/>
-Restrict to local access only<br/>
-Username: api<br/>
-Uncheck "Use a pre-defined role"<br/>
-Network: Full Management<br/>
-Protect: None<br/>
-OS Setting: None

### Available Script Parameters:<br/>
[switch]$EvaluationOnly - View potential changes without committing<br/>
[switch]$TestOnly - Attempt to add 2 A Records (test and test2 with IPs of 192.168.99.998 and 192.168.99.999)<br/>