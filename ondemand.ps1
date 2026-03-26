$username = "YOUR_USERNAME"
$password = "YOUR_PASSWORD"

# Step 1: Start authentication
$step1 = Invoke-RestMethod `
    -Uri "https://ondemand.fiserv.com/api/v1/token" `
    -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "grant_type=password&username=$username&password=$password"

$mfaAccessToken = $step1.mfa_access_token

# Optional step: trigger OTP delivery if needed by this configuration
Invoke-RestMethod `
    -Uri "https://ondemand.fiserv.com/api/v1/token/otp" `
    -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "mfa_access_token=$mfaAccessToken"

$otp = Read-Host "Enter OTP code"

# Step 2: Complete MFA and get the real API access token
$step2 = Invoke-RestMethod `
    -Uri "https://ondemand.fiserv.com/api/v1/token" `
    -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "grant_type=otp&username=$username&password=$password&mfa_access_token=$mfaAccessToken&otp=$otp"

$accessToken = $step2.access_token

$headers = @{
    Authorization = "Bearer $accessToken"
}

# Validation call
Invoke-RestMethod `
    -Uri "https://ondemand.fiserv.com/api/v1/users/self" `
    -Method Get `
    -Headers $headers
