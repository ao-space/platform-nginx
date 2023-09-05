FROM nginx:1.23.3

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && rm -rf /etc/nginx/conf.d/default.conf

EXPOSE 80 443

CMD ["/entrypoint.sh"]