provider "aws" {
  region     = "ap-south-1"
  profile    = "nitin"
}

resource "aws_key_pair" "deployer" {
  key_name   = "my_key1"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCwe7aECB8iQwuBT2UETinG8NFn+HUI9QCneqq7VBaY3NApbWM1OYkMYplet36B8rUTIuyCrJJOnPsQoDAOJzx8Dqm5g7hbePhh5E2vM3aWyqo60vgR5gN3+j3TT2UsZfWw/Unhw1I0nCHvBmSxll/Iv4TCPcoXcGa+z4BYKPuJ/UtG1IOblv1lThjSM4PFhUIZqL7n/DGuXn4Wa7aEhOk1YFEMFreSguVIBCxxRHn0yK2VscougYPIP580ekp1kFjGASd6Wg7lYiFxJZopZmwbl5flRjr+i129Cdg9tPlGwloKotlPtoTriaVTKnYhuLwlWLsX0N18Kr6I07vuQuQ9"
}

resource "aws_security_group" "allow_ssh_http" {

  name        = "allow_ssh_http"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-0809dc9f0a9abb3a1"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_ssh"
  }
}


resource "aws_ebs_volume" "ebs_vol_create" {
  depends_on = [
    aws_security_group.allow_ssh_http,
  ]
  availability_zone = "ap-south-1a"
  size              = 1
  
  tags = {
    Name = "ebs"
  }
}


resource "aws_instance" "inst" {
  depends_on = [
    aws_ebs_volume.ebs_vol_create,
  ]
  ami           = "ami-0a780d5bac870126a"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "my_key"
  security_groups = ["allow_ssh_http"]
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/91704/Downloads/my_key.pem")
    host     = aws_instance.inst.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install git -y",
      "sudo yum install httpd -y",
      "sudo service httpd start",
    ]
  }
  tags = {
    Name = "Os"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  depends_on = [
    aws_ebs_volume.ebs_vol_create,aws_instance.inst,
  ]
  device_name = "/dev/sdf"
  volume_id   = "${aws_ebs_volume.ebs_vol_create.id}"
  instance_id = "${aws_instance.inst.id}"
  force_detach = true
}

resource "null_resource" "public_ip" {
     depends_on = [
    aws_instance.inst,
  ]
	provisioner "local-exec" {
		command = "echo ${aws_instance.inst.public_ip} > publicip.txt"
	}
}

resource "null_resource" "ebs_mount"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/91704/Downloads/my_key.pem")
    host     = aws_instance.inst.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdf",
      "sudo mount  /dev/xvdf  /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Nitingupta315/Task-1.git /var/www/html/"
    ]
  }
}


resource "aws_s3_bucket" "terra_bucket" {
  depends_on = [
    aws_instance.inst,
  ]
  bucket = "buckt1ng"
  acl = "public-read"

  tags = {
    Name        = "buckt1ng"
    Environment = "Dev"
  }
}
resource "null_resource" "git_base"  {

  depends_on = [
    aws_s3_bucket.terra_bucket,
  ]
   provisioner "local-exec" {
    working_dir="C:/Users/91704/Desktop/Task_1/"
    command ="mkdir git_terra"
  }
  provisioner "local-exec" {
    working_dir="C:/Users/91704/Desktop/Task_1"
    command ="git clone https://github.com/Nitingupta315/Task-1.git  C:/Users/91704/Desktop/Task_1"
  }
   
}



resource "aws_s3_bucket_object" "s3_upload" {
  depends_on = [
    null_resource.git_base,
  ]
  for_each = fileset("C:/Users/91704/Desktop/Task_1/", "*.png")

  bucket = "terrabucg"
  key    = each.value
  source = "C:/Users/91704/Desktop/Task_1/${each.value}"
  etag   = filemd5("C:/Users/91704/Desktop/Task_1/${each.value}")
  acl = "public-read"

}


locals {
  s3_origin_id = "s3-${aws_s3_bucket.terra_bucket.id}"
}

resource "aws_cloudfront_distribution" "s3_cloud" {
  depends_on = [
    aws_s3_bucket_object.s3_upload,
  ]
  origin {
    domain_name = "${aws_s3_bucket.terra_bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Terraform connecting s3 to the cloudfront"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "updating_code"  {

  depends_on = [
    aws_cloudfront_distribution.s3_cloud,
  ]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("C:/Users/91704/Downloads/my_key.pem")
    host = aws_instance.inst.public_ip
	}
  for_each = fileset("C:/Users/91704/Desktop/Task_1/", "*.png")
  provisioner "remote-exec" {
    inline = [
	"sudo su << EOF",
	"echo \"<p>Image access using cloud front url</p>\" >> /var/www/html/index.html",
	"echo \"<img src='http://${aws_cloudfront_distribution.s3_cloud.domain_name}/${each.value}' width='500' height='333'>\" >> /var/www/html/index.html",
        "EOF"
			]
	}
	 provisioner "local-exec" {
		command = "start chrome  ${aws_instance.inst.public_ip}/index.html"
	}

}