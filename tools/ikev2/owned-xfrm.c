/* Match both reserved IDs; never flush a namespace or print SA key material. */
#define _GNU_SOURCE
#include <errno.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/xfrm.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define OWN_ID 20290U
#define MAX_OWNED 256
struct item {
 int policy;
 union { struct xfrm_userpolicy_id policy; struct xfrm_usersa_id sa; } id;
 struct xfrm_mark mark;
};
static struct item items[MAX_OWNED];
static unsigned count, policies, states;
static uint32_t sequence;
static int fd;
static void die(const char *s) { perror(s); exit(1); }
static void require(int value, const char *s) { if (!value) { fprintf(stderr,"%s\n",s);exit(1); } }
static void wipe(void *p,size_t n) { volatile unsigned char *v=p;while(n--)*v++=0; }

static int parse(struct nlmsghdr *h,struct item *result) {
 int policy=h->nlmsg_type==XFRM_MSG_NEWPOLICY;
 if(!policy && h->nlmsg_type!=XFRM_MSG_NEWSA)return 0;
 size_t body=policy?sizeof(struct xfrm_userpolicy_info):sizeof(struct xfrm_usersa_info);
 require(h->nlmsg_len>=NLMSG_LENGTH(body),"Short XFRM message");
 uint32_t if_id=0;int own=0;
 memset(result,0,sizeof(*result));result->policy=policy;
 if(policy){
  struct xfrm_userpolicy_info *p=NLMSG_DATA(h);
  result->id.policy.sel=p->sel;result->id.policy.index=p->index;result->id.policy.dir=p->dir;
 }else{
  struct xfrm_usersa_info *s=NLMSG_DATA(h);
  own=s->reqid==OWN_ID;
  result->id.sa.daddr=s->id.daddr;result->id.sa.spi=s->id.spi;
  result->id.sa.family=s->family;result->id.sa.proto=s->id.proto;
 }
 int remaining=(int)h->nlmsg_len-(int)NLMSG_LENGTH(body);
 struct rtattr *a=(struct rtattr *)((char *)NLMSG_DATA(h)+NLMSG_ALIGN(body));
 for(;RTA_OK(a,remaining);a=RTA_NEXT(a,remaining)){
  if(a->rta_type==XFRMA_IF_ID){
   require(RTA_PAYLOAD(a)==sizeof(if_id),"Invalid interface-ID attribute");memcpy(&if_id,RTA_DATA(a),sizeof(if_id));
  }else if(a->rta_type==XFRMA_MARK){
   require(RTA_PAYLOAD(a)==sizeof(result->mark),"Invalid mark attribute");memcpy(&result->mark,RTA_DATA(a),sizeof(result->mark));
  }else if(policy && a->rta_type==XFRMA_TMPL){
   require(RTA_PAYLOAD(a)>0 && RTA_PAYLOAD(a)%sizeof(struct xfrm_user_tmpl)==0,"Invalid policy templates");
   struct xfrm_user_tmpl *t=RTA_DATA(a);own=1;
   for(unsigned i=0;i<RTA_PAYLOAD(a)/sizeof(*t);i++)if(t[i].reqid!=OWN_ID)own=0;
  }
 }
 require(remaining==0,"Truncated XFRM attributes");
 return own && if_id==OWN_ID;
}
static void attr(struct nlmsghdr *h,int type,const void *data,size_t length){
 struct rtattr *a=(void *)((char *)h+NLMSG_ALIGN(h->nlmsg_len));
 a->rta_type=type;a->rta_len=RTA_LENGTH(length);memcpy(RTA_DATA(a),data,length);
 h->nlmsg_len=NLMSG_ALIGN(h->nlmsg_len)+RTA_ALIGN(a->rta_len);
}
static void send_request(struct nlmsghdr *h){
 struct sockaddr_nl kernel={.nl_family=AF_NETLINK};h->nlmsg_seq=++sequence;
 if(sendto(fd,h,h->nlmsg_len,0,(void *)&kernel,sizeof(kernel))!=(ssize_t)h->nlmsg_len)die("XFRM request");
}
static ssize_t receive(char *buffer,size_t size){
 struct sockaddr_nl sender={0};struct iovec iov={buffer,size};
 struct msghdr msg={.msg_name=&sender,.msg_namelen=sizeof(sender),.msg_iov=&iov,.msg_iovlen=1};
 ssize_t length=recvmsg(fd,&msg,0);if(length<0)die("XFRM response");
 require(length>0 && !(msg.msg_flags&MSG_TRUNC) && sender.nl_pid==0,"Invalid kernel response");return length;
}
static void collect(int policy){
 char request[NLMSG_SPACE(sizeof(struct xfrm_userpolicy_id))]={0};
 struct nlmsghdr *h=(void *)request;h->nlmsg_type=policy?XFRM_MSG_GETPOLICY:XFRM_MSG_GETSA;
 h->nlmsg_len=NLMSG_LENGTH(policy?sizeof(struct xfrm_userpolicy_id):sizeof(struct xfrm_usersa_id));
 h->nlmsg_flags=NLM_F_REQUEST|NLM_F_DUMP;send_request(h);
 char buffer[65536];
 for(;;){
  ssize_t size=receive(buffer,sizeof(buffer));int remaining=(int)size;
  for(h=(void *)buffer;NLMSG_OK(h,remaining);h=NLMSG_NEXT(h,remaining)){
   require(h->nlmsg_seq==sequence && !(h->nlmsg_flags&NLM_F_DUMP_INTR),"Interrupted XFRM dump");
   if(h->nlmsg_type==NLMSG_DONE){
    if(NLMSG_PAYLOAD(h,0)>=sizeof(int)){int error;memcpy(&error,NLMSG_DATA(h),sizeof(error));require(error==0,"XFRM dump failed");}
    wipe(buffer,sizeof(buffer));return;
   }
   if(h->nlmsg_type==NLMSG_ERROR){
    require(h->nlmsg_len>=NLMSG_LENGTH(sizeof(struct nlmsgerr)),"Short netlink error");
    errno=-((struct nlmsgerr *)NLMSG_DATA(h))->error;die("XFRM dump");
   }
   struct item item;
   if(parse(h,&item)){
    require(count<MAX_OWNED,"Too many owned XFRM entries; nothing deleted");items[count++]=item;
    if(policy)policies++;else states++;
   }
  }
  require(remaining==0,"Truncated netlink dump");wipe(buffer,sizeof(buffer));
 }
}
static void remove_item(struct item *item){
 char request[NLMSG_SPACE(sizeof(struct xfrm_userpolicy_id))+128]={0};
 struct nlmsghdr *h=(void *)request;h->nlmsg_type=item->policy?XFRM_MSG_DELPOLICY:XFRM_MSG_DELSA;
 size_t length=item->policy?sizeof(item->id.policy):sizeof(item->id.sa);
 h->nlmsg_len=NLMSG_LENGTH(length);h->nlmsg_flags=NLM_F_REQUEST|NLM_F_ACK;
 memcpy(NLMSG_DATA(h),&item->id,length);uint32_t id=OWN_ID;
 attr(h,XFRMA_IF_ID,&id,sizeof(id));
 if(item->mark.m || item->mark.v)attr(h,XFRMA_MARK,&item->mark,sizeof(item->mark));
 send_request(h);char buffer[4096];ssize_t size=receive(buffer,sizeof(buffer));
 h=(void *)buffer;
 require(NLMSG_OK(h,size) && h->nlmsg_seq==sequence && h->nlmsg_type==NLMSG_ERROR &&
         h->nlmsg_len>=NLMSG_LENGTH(sizeof(struct nlmsgerr)),"Invalid deletion acknowledgement");
 int error=((struct nlmsgerr *)NLMSG_DATA(h))->error;
 if(error && error!=-ENOENT){errno=-error;die("Owned XFRM deletion");}
}
#ifndef OWNED_XFRM_TEST
int main(int argc,char **argv){
 require(argc==2 && (!strcmp(argv[1],"--check") || !strcmp(argv[1],"--delete-owned")),"Usage: owned-xfrm --check|--delete-owned");
 int remove=!strcmp(argv[1],"--delete-owned");
 fd=socket(AF_NETLINK,SOCK_RAW|SOCK_CLOEXEC,NETLINK_XFRM);if(fd<0)die("XFRM socket");
 struct sockaddr_nl local={.nl_family=AF_NETLINK};
 if(bind(fd,(void *)&local,sizeof(local)))die("XFRM bind");
 struct timeval timeout={.tv_sec=3};if(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)))die("XFRM timeout");
 collect(1);collect(0);
 printf("owned_policies=%u owned_states=%u\n",policies,states);
 if(remove){
  for(unsigned i=0;i<count;i++)remove_item(&items[i]);
  count=policies=states=0;collect(1);collect(0);
  require(count==0,"Owned XFRM entries remain");puts("owned_cleanup_complete");
 }
 close(fd);return 0;
}
#endif
