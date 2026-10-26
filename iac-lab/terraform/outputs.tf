output "server_public_ip" {
  description = "Public IP of the EC2 server"
  value       = aws_instance.web.public_ip
}

output "app_url" {
  description = "Open this in your browser after the deploy"
  value       = "http://${aws_instance.web.public_ip}"
}

output "ssh_command" {
  description = "How to log in to the server"
  value       = "ssh -i ~/.ssh/iac-lab ubuntu@${aws_instance.web.public_ip}"
}

output "artifacts_bucket" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.artifacts.bucket
}
