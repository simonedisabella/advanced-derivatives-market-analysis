function y = BSPrice(S,K,r,q,T,vol,PutCall)

d1 = (log(S/K) + (r-q+vol^2/2)*T)/vol/sqrt(T);
d2 = d1 - vol*sqrt(T);

Nd1 = cdf('norm',d1,0,1);
Nd2 = cdf('norm',d2,0,1);

Call = S*exp(-q*T)*Nd1 - K*exp(-r*T)*Nd2;

if strcmp(PutCall,'C')
    y = Call;
else
    y = Call + exp(-r*T)*K - exp(-q*T)*S;
end


