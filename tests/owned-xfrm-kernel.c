#define _GNU_SOURCE
#include <arpa/inet.h>
#define OWNED_XFRM_TEST
#include "../tools/ikev2/owned-xfrm.c"
#include <assert.h>
#include <sched.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/wait.h>
static const struct xfrm_lifetime_cfg lifetime={.soft_byte_limit=XFRM_INF,.hard_byte_limit=XFRM_INF,.soft_packet_limit=XFRM_INF,.hard_packet_limit=XFRM_INF};
static void ack(struct nlmsghdr *h){
 send_request(h);char buffer[4096];int length=(int)receive(buffer,sizeof(buffer));h=(void *)buffer;
 assert(NLMSG_OK(h,length) && h->nlmsg_seq==sequence && h->nlmsg_type==NLMSG_ERROR);
 int error=((struct nlmsgerr *)NLMSG_DATA(h))->error;if(error){errno=-error;die("Kernel test fixture");}
}
static void add_policy(unsigned number,uint32_t reqid,uint32_t ifid){
 char buffer[2048]={0};struct nlmsghdr *h=(void *)buffer;
 h->nlmsg_type=XFRM_MSG_NEWPOLICY;h->nlmsg_flags=NLM_F_REQUEST|NLM_F_ACK|NLM_F_CREATE|NLM_F_EXCL;
 h->nlmsg_len=NLMSG_LENGTH(sizeof(struct xfrm_userpolicy_info));
 struct xfrm_userpolicy_info *p=NLMSG_DATA(h);p->sel.family=AF_INET;p->sel.prefixlen_s=32;
 p->sel.saddr.a4=htonl(0x0a630000+number);p->dir=XFRM_POLICY_OUT;p->action=XFRM_POLICY_ALLOW;p->priority=1000;p->lft=lifetime;
 struct xfrm_user_tmpl tmpl={.family=AF_INET,.mode=XFRM_MODE_TUNNEL,.reqid=reqid,.aalgos=~0U,.ealgos=~0U,.calgos=~0U};
 tmpl.id.proto=50;tmpl.id.daddr.a4=htonl(0xc0000202);tmpl.saddr.a4=htonl(0xc0000201);
 attr(h,XFRMA_TMPL,&tmpl,sizeof(tmpl));attr(h,XFRMA_IF_ID,&ifid,sizeof(ifid));ack(h);
}
static void add_state(unsigned number,uint32_t reqid,uint32_t ifid){
 char buffer[2048]={0};struct nlmsghdr *h=(void *)buffer;
 h->nlmsg_type=XFRM_MSG_NEWSA;h->nlmsg_flags=NLM_F_REQUEST|NLM_F_ACK|NLM_F_CREATE|NLM_F_EXCL;
 h->nlmsg_len=NLMSG_LENGTH(sizeof(struct xfrm_usersa_info));
 struct xfrm_usersa_info *s=NLMSG_DATA(h);s->family=AF_INET;s->sel.family=AF_INET;s->mode=XFRM_MODE_TUNNEL;
 s->reqid=reqid;s->id.proto=50;s->id.spi=htonl(0x10000+number);s->id.daddr.a4=htonl(0xc0000202);s->saddr.a4=htonl(0xc0000201);
 s->replay_window=32;s->lft=lifetime;
 char algorithm[sizeof(struct xfrm_algo_aead)+20]={0};struct xfrm_algo_aead *a=(void *)algorithm;
 strcpy(a->alg_name,"rfc4106(gcm(aes))");a->alg_key_len=160;a->alg_icv_len=128;
 for(unsigned i=0;i<20;i++)a->alg_key[i]=(char)i;
 attr(h,XFRMA_ALG_AEAD,a,sizeof(algorithm));attr(h,XFRMA_IF_ID,&ifid,sizeof(ifid));ack(h);
}
static unsigned total(int policy){
 char request[NLMSG_SPACE(sizeof(struct xfrm_userpolicy_id))]={0},buffer[65536];
 struct nlmsghdr *h=(void *)request;h->nlmsg_type=policy?XFRM_MSG_GETPOLICY:XFRM_MSG_GETSA;
 h->nlmsg_len=NLMSG_LENGTH(policy?sizeof(struct xfrm_userpolicy_id):sizeof(struct xfrm_usersa_id));
 h->nlmsg_flags=NLM_F_REQUEST|NLM_F_DUMP;send_request(h);unsigned result=0;
 for(;;){
  int length=(int)receive(buffer,sizeof(buffer));
  for(h=(void *)buffer;NLMSG_OK(h,length);h=NLMSG_NEXT(h,length)){
   assert(h->nlmsg_seq==sequence);
   if(h->nlmsg_type==NLMSG_DONE){wipe(buffer,sizeof(buffer));return result;}
   assert(h->nlmsg_type!=NLMSG_ERROR);if(h->nlmsg_type==(policy?XFRM_MSG_NEWPOLICY:XFRM_MSG_NEWSA))result++;
  }
  assert(length==0);wipe(buffer,sizeof(buffer));
 }
}
static void run_helper(const char *path){
 pid_t pid=fork();assert(pid>=0);
 if(!pid){execl(path,path,"--delete-owned",(char *)NULL);_exit(127);}
 int status;assert(waitpid(pid,&status,0)==pid);assert(WIFEXITED(status) && WEXITSTATUS(status)==0);
}
int main(int argc,char **argv){
 struct rlimit no_core={0,0};assert(setrlimit(RLIMIT_CORE,&no_core)==0);
 assert(argc==2 && argv[1][0]=='/');
 struct stat before,after;assert(stat("/proc/self/ns/net",&before)==0);
 if(unshare(CLONE_NEWNET))die("Isolated network namespace required; no fixture created");
 assert(stat("/proc/self/ns/net",&after)==0 && before.st_ino!=after.st_ino);
 puts("ISOLATED_NETWORK_NAMESPACE_CONFIRMED");
 fd=socket(AF_NETLINK,SOCK_RAW|SOCK_CLOEXEC,NETLINK_XFRM);assert(fd>=0);
 struct sockaddr_nl local={.nl_family=AF_NETLINK};assert(bind(fd,(void *)&local,sizeof(local))==0);
 struct timeval timeout={.tv_sec=3};assert(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout))==0);
 assert(total(1)==0 && total(0)==0);
 uint32_t reqids[]={OWN_ID,OWN_ID,99,OWN_ID},ids[]={OWN_ID,99,OWN_ID,0};
 for(unsigned i=0;i<4;i++){add_policy(i+1,reqids[i],ids[i]);add_state(i+1,reqids[i],ids[i]);}
 assert(total(1)==4 && total(0)==4);collect(1);collect(0);assert(policies==1 && states==1);
 run_helper(argv[1]);
 assert(total(1)==3 && total(0)==3);
 count=policies=states=0;collect(1);collect(0);assert(count==0);
 run_helper(argv[1]);
 assert(total(1)==3 && total(0)==3);close(fd);
 puts("PASS: real kernel deletion retains foreign policies/states and is idempotent");return 0;
}
