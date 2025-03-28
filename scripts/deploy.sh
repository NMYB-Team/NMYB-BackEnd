#!/bin/bash

# 변수 설정
PROJECT_DIR="/home/ubuntu/nmnb"
NGINX_CONF_DIR="/home/ubuntu/nginx"

COMPOSE_PATH="$PROJECT_DIR/docker-compose.override.yml"
ENV_FILE_PATH="/home/ubuntu/.env"

NGINX_CONTAINER="nginx"
DELAY=10

# 현재 실행 중인 블루 컨테이너 확인
BLUE_API_CONTAINER="$(docker ps --filter "name=nmnb-blue" --filter "status=running" | grep -v "CONTAINER ID")"

# 컨테이너 환경 스위칭
if [[ -n "$BLUE_API_CONTAINER" ]]; then
    echo "-----------------------------"
    echo "전환: BLUE => GREEN"
    echo "-----------------------------"

    CURRENT_API_ENV='nmnb-blue'
    NEW_API_ENV='nmnb-green'

    CURRENT_NGINX_CONF='nmnb.blue.conf'
    NEW_NGINX_CONF='nmnb.green.conf'
else
    echo "-----------------------------"
    echo "전환: GREEN => BLUE"
    echo "-----------------------------"

    CURRENT_API_ENV='nmnb-green'
    NEW_API_ENV='nmnb-blue'

    CURRENT_NGINX_CONF='nmnb.green.conf'
    NEW_NGINX_CONF='nmnb.blue.conf'
fi

# .env 파일을 Docker Compose가 인식할 수 있는 위치로 복사
echo
echo "-----------------------------"
echo "배포된 .env 파일을 Docker Compose가 인식할 수 있도록 복사 중..."
cp "$ENV_FILE_PATH" "$PROJECT_DIR/.env" || { echo ".env 파일 복사 실패"; exit 1; }
echo ".env 파일 복사 완료"
echo "-----------------------------"
echo

# 새로운 이미지 빌드 (캐시 무시)
echo
echo "-----------------------------"
echo "새로운 환경 이미지 빌드 중: $NEW_API_ENV (캐시 무시)"
sudo docker-compose -f "$COMPOSE_PATH" build --no-cache $NEW_API_ENV || { echo "이미지 빌드 실패"; exit 1; }
echo "이미지 빌드 완료"
echo "-----------------------------"
echo

# 새로운 컨테이너 시작
echo
echo "-----------------------------"
echo "새로운 환경 시작 중: $NEW_API_ENV"
sudo docker-compose -f "$COMPOSE_PATH" up -d --no-deps $NEW_API_ENV || { echo "새로운 환경 시작 실패"; exit 1; }
echo "새로운 환경 시작 완료"
echo "-----------------------------"
echo

# 컨테이너 시작 대기
sleep $DELAY

# 컨테이너 정상 실행 여부 확인
if ! docker ps --filter "name=$NEW_API_ENV" --filter "status=running" | grep -q "$NEW_API_ENV"; then
    echo "새로운 환경($NEW_API_ENV) 컨테이너가 정상 실행되지 않음"
    exit 1
fi

# Nginx 설정 파일 업데이트
echo
echo "-----------------------------"
echo "Nginx 설정 파일 업데이트 중..."
docker cp "$NGINX_CONF_DIR/$NEW_NGINX_CONF" "$NGINX_CONTAINER:/etc/nginx/conf.d/"

echo "복사된 파일 확인"
docker exec "$NGINX_CONTAINER" ls -l /etc/nginx/conf.d/

echo "현재 설정 파일 삭제"
docker exec "$NGINX_CONTAINER" rm -f "/etc/nginx/conf.d/$CURRENT_NGINX_CONF"
echo "-----------------------------"
echo

echo "남아있는 파일 확인"
docker exec "$NGINX_CONTAINER" ls -l /etc/nginx/conf.d/

# Nginx 설정 테스트 및 리로드
echo
echo "-----------------------------"
echo "Nginx 설정 테스트 중..."
docker exec "$NGINX_CONTAINER" nginx -t || { echo "Nginx 설정 오류"; exit 1; }
echo "Nginx 설정 문제 없음"

echo "Nginx 리로드 중..."
docker exec "$NGINX_CONTAINER" nginx -s reload || { echo "Nginx 리로드 실패"; exit 1; }
echo "Nginx 리로드 완료"
echo "-----------------------------"
echo

# 이전 환경 중지 및 제거
echo
echo "-----------------------------"
echo "이전 환경 중지 및 제거 중: $CURRENT_API_ENV"
sudo docker-compose -f "$COMPOSE_PATH" stop "$CURRENT_API_ENV" || { echo "이전 환경 중지 실패"; exit 1; }
sudo docker-compose -f "$COMPOSE_PATH" rm -f "$CURRENT_API_ENV" || { echo "이전 환경 제거 실패"; exit 1; }
echo "이전 환경 중지 및 제거 완료"
echo "-----------------------------"
echo

# 불필요한 이미지 정리
echo
echo "-----------------------------"
echo "불필요한 이미지 및 컨테이너 정리 중..."
docker system prune -a -f || { echo "docker system prune 실패"; exit 1; }
echo "불필요한 리소스 정리 완료"
echo "-----------------------------"

# 배포 완료 메시지 (여기까지 오면 성공한 것)
echo
echo "-----------------------------"
echo "✅ 배포가 완료되었습니다!"
echo "-----------------------------"
