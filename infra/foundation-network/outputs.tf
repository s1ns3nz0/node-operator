output "network" {
  value = {
    vpc_id                = aws_vpc.this.id
    system_subnet_ids     = aws_subnet.system[*].id
    hoodi_subnet_ids      = [aws_subnet.hoodi.id]
    system_route_table_id = aws_route_table.system.id
    hoodi_route_table_id  = aws_route_table.hoodi.id
    hoodi_nat_gateway_id  = aws_nat_gateway.hoodi.id
    hoodi_nat_public_ip   = aws_eip.hoodi_nat.public_ip
  }
}
