import numpy as np
cimport numpy as np
cimport cython

# TO DO: REFACTOR AND COMBINE THESE SCRIPTS TO USE A SINGLE KALMAN FILTER/SMOOTHER SCRIPT
# Main differences between these functions are whether they treat certain matrices as
# constant or not

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def univariate_KFS(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering and smoothing for univariate time series

    Notes
    ----------

    y = mu + Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    alpha : np.array
        Smoothed states

    V : np.array
        Variance of smoothed states
    """     

    # Filtering matrices
    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed
    cdef np.ndarray[double, ndim=3, mode="c"] L = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]), dtype=np.float64)

    # Smoothing matrices
    cdef np.ndarray[double, ndim=3, mode="c"] N = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] V = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] alpha = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r_star = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] K_star = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] N_star = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] e = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] D = np.zeros((a.shape[0],a.shape[0],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    # FORWARDS (FILTERING)
    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu
        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]
        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]
        L[:,:,t] = T - np.dot(K[:,t],Z)
        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 
        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    for t in reversed(range(y.shape[0])):
        if t != 0:
            r_star[:,t] = np.dot(T.T,r[:,t])
            N_star[:,:,t] = np.dot(T,np.dot(N[:,:,t],T.T))
            K_star[:,t] = np.dot(N_star[:,:,t],K[:,t])
            e[t] = np.dot(np.linalg.inv(F[:,:,t]),v[t]) - np.dot(K[:,t].T,r_star[:,t])
            D[:,:,t] = np.linalg.inv(F[:,:,t]) + np.dot(K[:,t],K_star[:,t].T)

            r[:,t-1] = np.dot(Z.T,e[t]) + r_star[:,t]
            N[:,:,t-1] = np.dot(Z.T,np.dot(D[:,:,t],Z))

            alpha[:,t] = a[:,t] + np.dot(P[:,:,t],r[:,t-1])
            V[:,:,t] = P[:,:,t] - np.dot(np.dot(P[:,:,t],N[:,:,t-1]),P[:,:,t])
        else:
            alpha[:,t] = a[:,t]
            V[:,:,t] = P[:,:,t]            

    return alpha, V

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def univariate_kalman(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    a : np.array
        Filtered states

    P : np.array
        Filtered variances

    K : np.array
        Kalman Gain matrices

    F : np.array
        Signal-to-noise term

    v : np.array
        Residuals
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu

        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P, K, F, v

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def univariate_kalman_fcst(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu, int h):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    h : int
        How many steps to forecast ahead!

    Returns
    ----------
    a : np.array
        Forecasted states

    P : np.array
        Variance of forecasted states
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1+h), dtype=np.float64)
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1+h), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]+h), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0]+h, dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]+h), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]+h):
        if t >= y.shape[0]:
            v[t] = 0
            F[:,:,t] = 10**7
            K[:,t] = np.zeros(a.shape[0])
        else:
            v[t] = y[t] - np.dot(Z,a[:,t]) - mu
            F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]
            K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def llt_univariate_KFS(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=1] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering and smoothing for univariate time series

    Notes
    ----------

    y = mu + Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    alpha : np.array
        Smoothed states

    V : np.array
        Variance of smoothed states
    """     

    # Filtering matrices
    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed
    cdef np.ndarray[double, ndim=3, mode="c"] L = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]), dtype=np.float64)

    # Smoothing matrices
    cdef np.ndarray[double, ndim=3, mode="c"] N = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] V = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] alpha = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r_star = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] K_star = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] N_star = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] e = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] D = np.zeros((a.shape[0],a.shape[0],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    # FORWARDS (FILTERING)
    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu
        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]
        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]
        L[:,:,t] = T - np.dot(K[:,t],Z)
        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 
        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    for t in reversed(range(y.shape[0])):
        if t != 0:
            r_star[:,t] = np.dot(T.T,r[:,t])
            N_star[:,:,t] = np.dot(T,np.dot(N[:,:,t],T.T))
            K_star[:,t] = np.dot(N_star[:,:,t],K[:,t])
            e[t] = np.dot(np.linalg.inv(F[:,:,t]),v[t]) - np.dot(K[:,t].T,r_star[:,t])
            D[:,:,t] = np.linalg.inv(F[:,:,t]) + np.dot(K[:,t],K_star[:,t].T)

            r[:,t-1] = np.dot(Z.T,e[t]) + r_star[:,t]
            N[:,:,t-1] = np.dot(Z.T,np.dot(D[:,:,t],Z))

            alpha[:,t] = a[:,t] + np.dot(P[:,:,t],r[:,t-1])
            V[:,:,t] = P[:,:,t] - np.dot(np.dot(P[:,:,t],N[:,:,t-1]),P[:,:,t])
        else:
            alpha[:,t] = a[:,t]
            V[:,:,t] = P[:,:,t]            

    return alpha, V

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def llt_univariate_kalman(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=1] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    a : np.array
        Filtered states

    P : np.array
        Filtered variances

    K : np.array
        Kalman Gain matrices

    F : np.array
        Signal-to-noise term

    v : np.array
        Residuals
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu

        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P, K, F, v

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def llt_univariate_kalman_fcst(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=1] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu, int h):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    h : int
        How many steps to forecast ahead!

    Returns
    ----------
    a : np.array
        Forecasted states

    P : np.array
        Variance of forecasted states
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1+h), dtype=np.float64)
    a[0][0] = np.mean(y[0:5]) # Initialization
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1+h), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]+h), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0]+h, dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]+h), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]+h):
        if t >= y.shape[0]:
            v[t] = 0
            F[:,:,t] = 10**7
            K[:,t] = np.zeros(a.shape[0])
        else:
            v[t] = y[t] - np.dot(Z,a[:,t]) - mu
            F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H.ravel()[0]
            K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P

def nl_univariate_KFS(y,Z,H,T,Q,R,mu):
    """ Kalman filtering and smoothing for univariate time series
    Notes
    ----------
    y = mu + Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION
    Parameters
    ----------
    y : np.array
        The time series data
    Z : np.array
        Design matrix for state matrix a
    H : np.array
        Covariance matrix for measurement noise
    T : np.array
        Design matrix for lagged state matrix in state equation
    Q : np.array
        Covariance matrix for state evolution noise
    R : np.array
        Scale matrix for state equation covariance matrix
    mu : float
        Constant term for measurement equation
    Returns
    ----------
    alpha : np.array
        Smoothed states
    V : np.array
        Variance of smoothed states
    """     

    # Filtering matrices
    a = np.zeros((T.shape[0],y.shape[0]+1)) # Initialization
    P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1))*(10**7) # diffuse prior asumed
    L = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1))
    K = np.zeros((a.shape[0],y.shape[0]))
    v = np.zeros(y.shape[0])
    F = np.zeros((1,1,y.shape[0]))

    # Smoothing matrices
    N = np.zeros((a.shape[0],a.shape[0],y.shape[0]))
    V = np.zeros((a.shape[0],a.shape[0],y.shape[0]))
    alpha = np.zeros((T.shape[0],y.shape[0])) 
    r = np.zeros((T.shape[0],y.shape[0])) 

    # FORWARDS (FILTERING)
    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu[t]

        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H[t].ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        L[:,:,t] = T - np.dot(K[:,t],Z)

        if t != (y.shape[0]-1):
        
            a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

            P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    # BACKWARDS (SMOOTHING)
    for t in reversed(range(y.shape[0])):
        if t != 0:
            L[:,:,t] = T - np.dot(K[:,t],Z)
            r[:,t-1] = np.dot(Z.T,v[t])/(F[:,:,t]).ravel()[0]
            N[:,:,t-1] = np.dot(Z.T,Z)/(F[:,:,t]).ravel()[0] + np.dot(np.dot(L[:,:,t].T,N[:,:,t]),L[:,:,t])
            alpha[:,t] = a[:,t] + np.dot(P[:,:,t],r[:,t-1])
            V[:,:,t] = P[:,:,t] - np.dot(np.dot(P[:,:,t],N[:,:,t-1]),P[:,:,t])
        else:
            alpha[:,t] = a[:,t]
            V[:,:,t] = P[:,:,t] 

    return alpha, V

def nl_univariate_kalman(y,Z,H,T,Q,R,mu):
    """ Kalman filtering for univariate time series
    Notes
    ----------
    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION
    Parameters
    ----------
    y : np.array
        The time series data
    Z : np.array
        Design matrix for state matrix a
    H : np.array
        Covariance matrix for measurement noise
    T : np.array
        Design matrix for lagged state matrix in state equation
    Q : np.array
        Covariance matrix for state evolution noise
    R : np.array
        Scale matrix for state equation covariance matrix
    mu : float
        Constant term for measurement equation
    Returns
    ----------
    a : np.array
        Filtered states
    P : np.array
        Filtered variances
    K : np.array
        Kalman Gain matrices
    F : np.array
        Signal-to-noise term
    v : np.array
        Residuals
    """         

    a = np.zeros((T.shape[0],y.shape[0]+1)) # Initialization
    P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1))*(10**7) # diffuse prior asumed

    K = np.zeros((a.shape[0],y.shape[0]))
    v = np.zeros(y.shape[0])
    F = np.zeros((1,1,y.shape[0]))

    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z,a[:,t]) - mu[t]

        F[:,:,t] = np.dot(np.dot(Z,P[:,:,t]),Z.T) + H[t].ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z.T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P, K, F, v


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def dl_univariate_KFS(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering and smoothing for univariate time series

    Notes
    ----------

    y = mu + Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    alpha : np.array
        Smoothed states

    V : np.array
        Variance of smoothed states
    """     

    # Filtering matrices
    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed
    cdef np.ndarray[double, ndim=3, mode="c"] L = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((1,1,y.shape[0]), dtype=np.float64)

    # Smoothing matrices
    cdef np.ndarray[double, ndim=3, mode="c"] N = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] V = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=2, mode="c"] alpha = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] r_star = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=2, mode="c"] K_star = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] N_star = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] e = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] D = np.zeros((a.shape[0],a.shape[0],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    # FORWARDS (FILTERING)
    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu

        F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H.ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        L[:,:,t] = T - np.dot(K[:,t],Z[t])

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))


    for t in reversed(range(y.shape[0])):
        if t != 0:
            r_star[:,t] = np.dot(T.T,r[:,t])
            N_star[:,:,t] = np.dot(T,np.dot(N[:,:,t],T.T))
            K_star[:,t] = np.dot(N_star[:,:,t],K[:,t])
            e[t] = np.dot(np.linalg.inv(F[:,:,t]),v[t]) - np.dot(K[:,t].T,r_star[:,t])
            D[:,:,t] = np.linalg.inv(F[:,:,t]) + np.dot(K[:,t],K_star[:,t].T)

            r[:,t-1] = np.dot(Z[t].T,e[t]) + r_star[:,t]
            N[:,:,t-1] = np.dot(Z[t].T,np.dot(D[:,:,t],Z[t]))

            alpha[:,t] = a[:,t] + np.dot(P[:,:,t],r[:,t-1])
            V[:,:,t] = P[:,:,t] - np.dot(np.dot(P[:,:,t],N[:,:,t-1]),P[:,:,t])
        else:
            alpha[:,t] = a[:,t]
            V[:,:,t] = P[:,:,t]            

    return alpha, V

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def dl_univariate_kalman(np.ndarray[double,ndim=1] y,np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    a : np.array
        Filtered states

    P : np.array
        Filtered variances

    K : np.array
        Kalman Gain matrices

    F : np.array
        Signal-to-noise term

    v : np.array
        Residuals
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1), dtype=np.float64) 
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0], dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu

        F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H.ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P, K, F, v

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def dl_univariate_kalman_fcst(np.ndarray[double,ndim=1] y, np.ndarray[double,ndim=2] Z, np.ndarray[double,ndim=2] H,
    np.ndarray[double,ndim=2] T, np.ndarray[double,ndim=2] Q, np.ndarray[double,ndim=2] R, double mu, int h):
    """ Kalman filtering for univariate time series

    Notes
    ----------

    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION

    Parameters
    ----------
    y : np.array
        The time series data

    Z : np.array
        Design matrix for state matrix a

    H : np.array
        Covariance matrix for measurement noise

    T : np.array
        Design matrix for lagged state matrix in state equation

    Q : np.array
        Covariance matrix for state evolution noise

    R : np.array
        Scale matrix for state equation covariance matrix

    mu : float
        Constant term for measurement equation

    Returns
    ----------
    a : np.array
        Forecasted states

    P : np.array
        Variance of forecasted states
    """         

    cdef np.ndarray[double, ndim=2, mode="c"] a = np.zeros((T.shape[0],y.shape[0]+1+h), dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1+h), dtype=np.float64)*(10**7) # diffuse prior asumed

    cdef np.ndarray[double, ndim=2, mode="c"] K = np.zeros((a.shape[0],y.shape[0]+h), dtype=np.float64)
    cdef np.ndarray[double, ndim=1, mode="c"] v = np.zeros(y.shape[0]+h, dtype=np.float64)
    cdef np.ndarray[double, ndim=3, mode="c"] F = np.zeros((H.shape[0],H.shape[1],y.shape[0]+h), dtype=np.float64)

    cdef Py_ssize_t t

    for t in range(0,y.shape[0]+h):
        if t >= y.shape[0]:
            v[t] = 0
            F[:,:,t] = 10**7
            K[:,t] = np.zeros(a.shape[0])
        else:
            v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu
            F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H.ravel()[0]
            K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P

def nld_univariate_KFS(y,Z,H,T,Q,R,mu):
    """ Kalman filtering and smoothing for univariate time series
    Notes
    ----------
    y = mu + Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION
    Parameters
    ----------
    y : np.array
        The time series data
    Z : np.array
        Design matrix for state matrix a
    H : np.array
        Covariance matrix for measurement noise
    T : np.array
        Design matrix for lagged state matrix in state equation
    Q : np.array
        Covariance matrix for state evolution noise
    R : np.array
        Scale matrix for state equation covariance matrix
    mu : float
        Constant term for measurement equation
    Returns
    ----------
    alpha : np.array
        Smoothed states
    V : np.array
        Variance of smoothed states
    """     

    # Filtering matrices
    a = np.zeros((T.shape[0],y.shape[0]+1)) # Initialization
    P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1))*(10**7) # diffuse prior asumed
    L = np.zeros((a.shape[0],a.shape[0],y.shape[0]+1))
    K = np.zeros((a.shape[0],y.shape[0]))
    v = np.zeros(y.shape[0])
    F = np.zeros((1,1,y.shape[0]))

    # Smoothing matrices
    N = np.zeros((a.shape[0],a.shape[0],y.shape[0]))
    V = np.zeros((a.shape[0],a.shape[0],y.shape[0]))
    alpha = np.zeros((T.shape[0],y.shape[0])) 
    r = np.zeros((T.shape[0],y.shape[0])) 

    # FORWARDS (FILTERING)
    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu[t]

        F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H[t].ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        L[:,:,t] = T - np.dot(K[:,t],Z[t])

        if t != (y.shape[0]-1):
        
            a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

            P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    # BACKWARDS (SMOOTHING)
    for t in reversed(range(y.shape[0])):
        if t != 0:
            L[:,:,t] = T - np.dot(K[:,t],Z[t])
            r[:,t-1] = np.dot(Z[t].T,v[t])/(F[:,:,t]).ravel()[0]
            N[:,:,t-1] = np.dot(Z[t].T,Z[t])/(F[:,:,t]).ravel()[0] + np.dot(np.dot(L[:,:,t].T,N[:,:,t]),L[:,:,t])
            alpha[:,t] = a[:,t] + np.dot(P[:,:,t],r[:,t-1])
            V[:,:,t] = P[:,:,t] - np.dot(np.dot(P[:,:,t],N[:,:,t-1]),P[:,:,t])
        else:
            alpha[:,t] = a[:,t]
            V[:,:,t] = P[:,:,t] 

    return alpha, V

def nld_univariate_kalman(y,Z,H,T,Q,R,mu):
    """ Kalman filtering for univariate time series
    Notes
    ----------
    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION
    Parameters
    ----------
    y : np.array
        The time series data
    Z : np.array
        Design matrix for state matrix a
    H : np.array
        Covariance matrix for measurement noise
    T : np.array
        Design matrix for lagged state matrix in state equation
    Q : np.array
        Covariance matrix for state evolution noise
    R : np.array
        Scale matrix for state equation covariance matrix
    mu : float
        Constant term for measurement equation
    Returns
    ----------
    a : np.array
        Filtered states
    P : np.array
        Filtered variances
    K : np.array
        Kalman Gain matrices
    F : np.array
        Signal-to-noise term
    v : np.array
        Residuals
    """         

    a = np.zeros((T.shape[0],y.shape[0]+1)) 
    P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1))*(10**7) # diffuse prior asumed

    K = np.zeros((a.shape[0],y.shape[0]))
    v = np.zeros(y.shape[0])
    F = np.zeros((H.shape[0],H.shape[1],y.shape[0]))

    for t in range(0,y.shape[0]):
        v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu[t]

        F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H[t].ravel()[0]

        K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P, K, F, v

def nld_univariate_kalman_fcst(y,Z,H,T,Q,R,mu,h):
    """ Kalman filtering for univariate time series
    Notes
    ----------
    y = Za_t + e_t         where   e_t ~ N(0,H)  MEASUREMENT EQUATION
    a_t = Ta_t-1 + Rn_t    where   n_t ~ N(0,Q)  STATE EQUATION
    Parameters
    ----------
    y : np.array
        The time series data
    Z : np.array
        Design matrix for state matrix a
    H : np.array
        Covariance matrix for measurement noise
    T : np.array
        Design matrix for lagged state matrix in state equation
    Q : np.array
        Covariance matrix for state evolution noise
    R : np.array
        Scale matrix for state equation covariance matrix
    mu : float
        Constant term for measurement equation
    Returns
    ----------
    a : np.array
        Forecasted states
    P : np.array
        Variance of forecasted states
    """         

    a = np.zeros((T.shape[0],y.shape[0]+1+h))
    P = np.ones((a.shape[0],a.shape[0],y.shape[0]+1+h))*(10**7) # diffuse prior asumed

    K = np.zeros((a.shape[0],y.shape[0]+h))
    v = np.zeros(y.shape[0]+h)
    F = np.zeros((H.shape[0],H.shape[1],y.shape[0]+h))

    for t in range(0,y.shape[0]+h):
        if t >= y.shape[0]:
            v[t] = 0
            F[:,:,t] = 10**7
            K[:,t] = np.zeros(a.shape[0])
        else:
            v[t] = y[t] - np.dot(Z[t],a[:,t]) - mu[t]
            F[:,:,t] = np.dot(np.dot(Z[t],P[:,:,t]),Z[t].T) + H[t].ravel()[0]
            K[:,t] = np.dot(np.dot(T,P[:,:,t]),Z[t].T)/(F[:,:,t]).ravel()[0]

        a[:,t+1] = np.dot(T,a[:,t]) + np.dot(K[:,t],v[t]) 

        P[:,:,t+1] = np.dot(np.dot(T,P[:,:,t]),T.T) + np.dot(np.dot(R,Q),R.T) - F[:,:,t].ravel()[0]*np.dot(np.array([K[:,t]]).T,np.array([K[:,t]]))

    return a, P