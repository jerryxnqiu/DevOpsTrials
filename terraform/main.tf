# Key commards
# terraform init
# terraform plan
# terraform apply --auto-approve
# terraform destroy --auto-approve

provider "aws" {
    region = var.region
    access_key = var.access_key
    secret_key = var.secret_key
}

# 1. Create VPC
resource "aws_vpc" "k8s-vpc" {
    cidr_block = "10.0.0.0/16"
    instance_tenancy = "default"
    assign_generated_ipv6_cidr_block = true
    tags = {
        Name = "k8s-vpc"
    }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "k8s-igw" {
    vpc_id = aws_vpc.k8s-vpc.id
    tags = {
        Name = "k8s-igw-ipv4"
    }
}

# 3. Create Custom Route Table
resource "aws_route_table" "k8s-routeTable" {
    vpc_id = aws_vpc.k8s-vpc.id

    # setup default route, send all traffic to gateway
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.k8s-igw.id
    }

    route {
        ipv6_cidr_block = "::/0"
        gateway_id = aws_internet_gateway.k8s-igw.id
    }

    tags = {
        Name = "k8s-routeTable"
    }
}

# 4. Create a Subnet
resource "aws_subnet" "k8s-subnet-1" {
    vpc_id = aws_vpc.k8s-vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = var.availabilityZone

    tags = {
        Name = var.subnet
    }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "k8s-routeTableAssoc" {
    subnet_id = aws_subnet.k8s-subnet-1.id
    route_table_id = aws_route_table.k8s-routeTable.id
}

# 6. Create Security Group to allow port for k8s
# Protocol	Direction	Port Range	Purpose	                Used By
# TCP	    Inbound	    6443	    Kubernetes API server	All
# TCP	    Inbound	    2379-2380	etcd server client API	kube-apiserver, etcd
# TCP	    Inbound	    10250	    Kubelet API	            Self, Control plane
# TCP	    Inbound	    10259	    kube-scheduler	        Self
# TCP	    Inbound	    10257	    kube-controller-manager	Self

resource "aws_security_group" "allow-k8s" {
    name        = "allow-k8s"
    description = "Allow K8s related inbound traffic"
    vpc_id      = aws_vpc.k8s-vpc.id

    ingress {
        description      = "Kubernetes API server"
        from_port        = 6443
        to_port          = 6443
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "etcd server client API"
        from_port        = 2379
        to_port          = 2380
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "Kubelet API"
        from_port        = 10250
        to_port          = 10250
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "kube-scheduler"
        from_port        = 10259
        to_port          = 10259
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "kube-controller-manager"
        from_port        = 10257
        to_port          = 10257
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "HTTPS"
        from_port        = 443
        to_port          = 443
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "HTTP"
        from_port        = 80
        to_port          = 80
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    ingress {
        description      = "SSH"
        from_port        = 22
        to_port          = 22
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    egress {
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    tags = {
        Name = "allow-k8s"
    }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "k8s-nic" {
    subnet_id       = aws_subnet.k8s-subnet-1.id
    private_ips     = ["10.0.1.50"]
    security_groups = [aws_security_group.allow-k8s.id]
}

# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
    vpc                       = true
    network_interface         = aws_network_interface.k8s-nic.id
    associate_with_private_ip = "10.0.1.50"
    depends_on                = [aws_internet_gateway.k8s-igw, aws_instance.k8s-master]
}

resource "aws_instance" "k8s-master" {
    ami                 = lookup(var.amis, var.region)
    instance_type       = var.instanceType
    availability_zone   = var.availabilityZone
    key_name            = var.keyName
    
    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.k8s-nic.id
    }

    tags = {
        Name = var.instanceName
    }

    user_data = "${file("setupk8s.sh")}"

}

