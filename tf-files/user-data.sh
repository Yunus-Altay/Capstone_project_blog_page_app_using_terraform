#!/bin/bash
apt-get update -y
apt-get install git -y
apt-get install python3 -y
cd /home/ubuntu/
TOKEN=${user-data-git-token}
git clone https://$TOKEN@github.com/Yunus-Altay/Capstone_project_blog_page_app_using_terraform.git
cd /home/ubuntu/Capstone_project_blog_page_app_using_terraform
apt install python3-pip -y
apt-get install python3.7-dev libmysqlclient-dev -y
pip3 install -r requirements.txt
cd /home/ubuntu/Capstone_project_blog_page_app_using_terraform/src/cblog
sed -i "s/'database_name'/'${rds_db_name}'/g" settings.py
sed -i "s/'user_name'/'${db_username}'/g" settings.py
sed -i "s/'database_endpoint'/'${db_endpoint}'/g" settings.py
sed -i "s/'bucket_id'/'${content_bucket_name}'/g" settings.py
sed -i "s/'bucket_region'/'${content_bucket_region}'/g" settings.py
cd /home/ubuntu/Capstone_project_blog_page_app_using_terraform/src
sed -i "s/'your DB password without any quotes'/'${db_password}'/g" .env
python3 manage.py collectstatic --noinput
python3 manage.py makemigrations
python3 manage.py migrate
python3 manage.py runserver 0.0.0.0:80